defmodule Marskal.Hydra do
  @moduledoc """
  Ory Hydra's admin API (ADR 0021). Hydra runs the OAuth protocol; the web
  app answers its login, consent, and device verification requests here,
  and introspects the tokens clients bring to the sync API.

  The admin API grants anything, so it is only ever reached on localhost.
  """

  @clients_dir "hydra/clients"

  @doc "Hydra's public base URL, where clients and browsers reach it."
  def public_url, do: config(:public_url)

  ## Device verification

  @doc "Confirms the code the user typed for a device challenge."
  def accept_user_code(device_challenge, user_code) do
    put("/admin/oauth2/auth/requests/device/accept", [device_challenge: device_challenge], %{
      user_code: user_code
    })
    |> redirect_to()
  end

  ## Login

  def get_login_request(challenge),
    do: get("/admin/oauth2/auth/requests/login", login_challenge: challenge)

  def accept_login(challenge, subject) do
    put("/admin/oauth2/auth/requests/login/accept", [login_challenge: challenge], %{
      subject: subject,
      remember: false
    })
    |> redirect_to()
  end

  def reject_login(challenge, error \\ "access_denied") do
    put("/admin/oauth2/auth/requests/login/reject", [login_challenge: challenge], %{error: error})
    |> redirect_to()
  end

  ## Consent

  def get_consent_request(challenge),
    do: get("/admin/oauth2/auth/requests/consent", consent_challenge: challenge)

  @doc """
  Grants `scopes`, and stamps the device's id on its access tokens, where
  `introspect/1` reads it back. Consent is not remembered: each device is
  its own consent, revoked alone.
  """
  def accept_consent(challenge, scopes, device_id) do
    put("/admin/oauth2/auth/requests/consent/accept", [consent_challenge: challenge], %{
      grant_scope: scopes,
      remember: false,
      session: %{access_token: %{device_id: device_id}}
    })
    |> redirect_to()
  end

  def reject_consent(challenge) do
    put("/admin/oauth2/auth/requests/consent/reject", [consent_challenge: challenge], %{
      error: "access_denied",
      error_description: "The user denied the request."
    })
    |> redirect_to()
  end

  ## Tokens and revocation

  @doc "What Hydra knows about a token. Inactive and unknown tokens are `{:ok, %{\"active\" => false}}`."
  def introspect(token), do: request(:post, "/admin/oauth2/introspect", form: [token: token])

  @doc "Revokes one consent, and so every token of that device."
  def revoke_consent(consent_request_id) do
    with {:ok, _} <-
           request(:delete, "/admin/oauth2/auth/sessions/consent",
             params: [consent_request_id: consent_request_id]
           ),
         do: :ok
  end

  @doc "Revokes every consent of a subject, and their tokens."
  def revoke_subject(subject) do
    with {:ok, _} <-
           request(:delete, "/admin/oauth2/auth/sessions/consent",
             params: [subject: subject, all: true]
           ),
         do: :ok
  end

  ## Setup

  @doc """
  Creates or updates every client in `priv/hydra/clients`, one JSON file
  per application, so a deploy converges on them. devenv sends the same
  files. Every copy of an application signs in as its one client.
  """
  def ensure_clients do
    dir = Application.app_dir(:marskal, Path.join("priv", @clients_dir))

    dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.sort()
    |> Enum.reduce_while(:ok, fn file, :ok ->
      spec = dir |> Path.join(file) |> File.read!() |> Jason.decode!()

      case ensure_client(spec) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp ensure_client(spec) do
    case request(:put, "/admin/clients/#{spec["client_id"]}", json: spec) do
      {:ok, _} -> :ok
      {:error, {404, _}} -> with {:ok, _} <- request(:post, "/admin/clients", json: spec), do: :ok
      {:error, _} = error -> error
    end
  end

  ## HTTP

  defp get(path, params), do: request(:get, path, params: params)
  defp put(path, params, body), do: request(:put, path, params: params, json: body)

  defp redirect_to({:ok, %{"redirect_to" => url}}), do: {:ok, url}
  defp redirect_to({:ok, _body}), do: {:error, :unexpected_response}
  defp redirect_to({:error, _} = error), do: error

  defp request(method, path, opts) do
    opts =
      [method: method, url: config(:admin_url) <> path, receive_timeout: 10_000, retry: false]
      |> Keyword.merge(opts)
      |> Keyword.merge(List.wrap(config(:req_options)))

    case Req.request(opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, exception} -> {:error, {:unreachable, exception}}
    end
  end

  defp config(key), do: Application.fetch_env!(:marskal, __MODULE__) |> Keyword.get(key)
end
