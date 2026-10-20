defmodule MarskalWeb.VisibilityController do
  use MarskalWeb, :controller

  alias MarskalWeb.Visibility

  @doc """
  Stores the browser's visibility choice on the session and the cookie.
  The LiveView hook posts here so a reconnect after a restart still has it.
  """
  def update(conn, %{"value" => value}) when is_binary(value) do
    key = get_session(conn, "visibility_key") || Visibility.new_key()
    visibility = Visibility.parse(value)
    Visibility.store(key, visibility)
    encoded = Visibility.encode(visibility)

    conn
    |> put_session("visibility_key", key)
    |> put_session("visibility", encoded)
    |> put_resp_cookie(Visibility.cookie(), encoded, Visibility.cookie_opts())
    |> send_resp(:no_content, "")
  end

  def update(conn, _params), do: send_resp(conn, 400, "")
end
