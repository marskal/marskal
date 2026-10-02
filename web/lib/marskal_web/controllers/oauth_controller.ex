defmodule MarskalWeb.OAuthController do
  @moduledoc """
  Hydra's login endpoint, and the metadata pointer (ADR 0021). Hydra sends
  the browser here with a `login_challenge` once the user has confirmed a
  device's code. The user is already signed in to the web app, so the login
  is accepted for them without asking again.
  """

  use MarskalWeb, :controller

  alias Marskal.Hydra

  def login(conn, %{"login_challenge" => challenge}) do
    user = conn.assigns.current_scope.user

    result =
      with {:ok, request} <- Hydra.get_login_request(challenge) do
        case request do
          # Hydra already knows this login; accept the same subject.
          %{"skip" => true, "subject" => subject} when subject != user.id ->
            Hydra.reject_login(challenge, "login_required")

          _ ->
            Hydra.accept_login(challenge, user.id)
        end
      end

    case result do
      {:ok, url} -> redirect(conn, external: url)
      {:error, _} -> redirect(conn, to: ~p"/oauth/error?#{[error: "login_failed"]}")
    end
  end

  def login(conn, _params), do: redirect(conn, to: ~p"/oauth/error?#{[error: "invalid_request"]}")

  @doc """
  Hydra serves the authorization server metadata (RFC 8414). In production
  the proxy sends this path straight to it; elsewhere the web app points
  there, so a client needs only the server's URL.
  """
  def metadata(conn, _params) do
    redirect(conn, external: Hydra.public_url() <> "/.well-known/oauth-authorization-server")
  end
end
