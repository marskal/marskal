defmodule Marskal.Imports.Todoist do
  @moduledoc """
  OAuth and the one-shot sync download for a Todoist import.

  The access token is used to fetch the snapshot and then discarded. New
  Todoist apps expire access tokens after an hour and rotate refresh tokens;
  this import keeps neither, so the next import signs in again. Scope is
  `data:read`.
  """

  @authorize_url "https://app.todoist.com/oauth/authorize"
  @token_url "https://api.todoist.com/oauth/access_token"
  @sync_url "https://api.todoist.com/api/v1/sync"
  @scope "data:read"
  @resource_types ~s(["user","projects","items","sections","labels","folders"])

  def configured? do
    present?(config(:client_id)) and present?(config(:client_secret))
  end

  def random_state do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  def authorize_url(redirect_uri, state) do
    query =
      URI.encode_query(%{
        "client_id" => config(:client_id),
        "scope" => @scope,
        "state" => state,
        "response_type" => "code",
        "redirect_uri" => redirect_uri
      })

    @authorize_url <> "?" <> query
  end

  @doc """
  The redirect URI sent to Todoist. `TODOIST_REDIRECT_URI` wins; otherwise
  the callback on `origin` (`scheme://host[:port]`).
  """
  def redirect_uri(origin) when is_binary(origin) do
    case config(:redirect_uri) do
      uri when is_binary(uri) and uri != "" -> uri
      _ -> String.trim_trailing(origin, "/") <> "/imports/todoist/callback"
    end
  end

  def exchange_code(code, redirect_uri) when is_binary(code) and code != "" do
    result =
      request(:post, @token_url,
        form: [
          client_id: config(:client_id),
          client_secret: config(:client_secret),
          code: code,
          redirect_uri: redirect_uri
        ]
      )

    case result do
      {:ok, %{"access_token" => token}} when is_binary(token) and token != "" ->
        {:ok, token}

      {:ok, %{"error" => error}} when is_binary(error) ->
        {:error, "Todoist did not sign you in (#{clip(error)})."}

      {:error, message} ->
        {:error, message}

      _ ->
        {:error, "Todoist did not sign you in."}
    end
  end

  def exchange_code(_code, _redirect_uri), do: {:error, "Todoist did not sign you in."}

  @doc "The sync JSON and the account label (an email, when Todoist sends one)."
  def fetch_snapshot(token) when is_binary(token) and token != "" do
    with {:ok, snapshot} <- sync(token) do
      if snapshot["sync_token"] || is_list(snapshot["projects"]) || is_list(snapshot["items"]) do
        {:ok, Jason.encode!(snapshot), account(snapshot)}
      else
        {:error, "Todoist returned an unexpected snapshot."}
      end
    end
  end

  def fetch_snapshot(_token), do: {:error, "Todoist did not sign you in."}

  defp sync(token) do
    result =
      request(:post, @sync_url,
        auth: {:bearer, token},
        form: [sync_token: "*", resource_types: @resource_types]
      )

    case result do
      {:ok, %{} = snapshot} -> {:ok, snapshot}
      {:ok, body} when is_binary(body) -> decode_snapshot(body)
      {:ok, _} -> {:error, "Todoist returned an unexpected snapshot."}
      {:error, message} -> {:error, message}
    end
  end

  defp decode_snapshot(body) do
    case Jason.decode(body) do
      {:ok, %{} = snapshot} -> {:ok, snapshot}
      _ -> {:error, "Todoist returned an unexpected snapshot."}
    end
  end

  defp account(snapshot) do
    case snapshot["user"] do
      %{"email" => email} when is_binary(email) and email != "" -> email
      %{"full_name" => name} when is_binary(name) and name != "" -> name
      _ -> nil
    end
  end

  defp request(method, url, opts) do
    opts =
      [method: method, url: url, receive_timeout: 60_000, redirect: false]
      |> Keyword.merge(opts)
      |> Keyword.merge(List.wrap(config(:req_options)))

    case Req.request(opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, http_error(status, body)}

      {:error, exception} ->
        {:error, "Could not reach Todoist (#{exception.__struct__})."}
    end
  end

  defp http_error(401, _body), do: "Todoist refused the sign-in."
  defp http_error(429, _body), do: "Todoist is rate limiting requests. Try again later."

  defp http_error(status, %{"error" => error}) when is_binary(error),
    do: "Todoist returned an error (#{status}: #{clip(error)})."

  defp http_error(status, _body), do: "Todoist returned an error (#{status})."

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(_value), do: false

  defp clip(text), do: text |> to_string() |> String.slice(0, 200)

  defp config(key) do
    :marskal
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key)
  end
end
