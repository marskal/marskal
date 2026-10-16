defmodule MarskalWeb.APIAuth do
  @moduledoc """
  Bearer access tokens for the sync API (ADR 0019, ADR 0021). Hydra issues
  them; this plug introspects each one, and refuses it unless it is live and
  its device is still signed in. A request without one gets `401`, and one
  whose grant lacks the scope gets `403`, each with the `WWW-Authenticate`
  header of RFC 6750.
  """

  import Plug.Conn
  alias Marskal.Accounts.Scope

  def init(opts), do: opts

  @doc """
  Sets `current_scope`, `device`, and `oauth_scopes` from the access token,
  and the token itself as `access_token`, for a stream that checks it again
  (ADR 0030).
  """
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         token = String.trim(token),
         {:ok, user, device, scopes} <- Marskal.Devices.authenticate(token) do
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> assign(:device, device)
      |> assign(:oauth_scopes, scopes)
      |> assign(:access_token, token)
    else
      [] -> deny(conn, 401, ~s(Bearer realm="marskal"))
      _ -> deny(conn, 401, ~s(Bearer realm="marskal", error="invalid_token"))
    end
  end

  @doc "Halts with `403` unless the token has `scope`."
  def require_scope(%{halted: true} = conn, _scope), do: conn

  def require_scope(conn, scope) do
    if scope in conn.assigns.oauth_scopes,
      do: conn,
      else: deny(conn, 403, ~s(Bearer error="insufficient_scope", scope="#{scope}"))
  end

  defp deny(conn, status, challenge) do
    error = if status == 403, do: "insufficient_scope", else: "invalid_token"

    conn
    |> put_resp_header("www-authenticate", challenge)
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: error}))
    |> halt()
  end
end
