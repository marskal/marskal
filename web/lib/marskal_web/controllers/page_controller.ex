defmodule MarskalWeb.PageController do
  use MarskalWeb, :controller

  alias MarskalWeb.UserAuth

  # / opens the user's home view. With none set, the open tasks.
  # A query, such as ?task=, comes along.
  def home(conn, _params) do
    redirect(conn, to: with_query(UserAuth.signed_in_path(conn), conn.query_string))
  end

  # Password managers open this to take the user to where a password is
  # changed (W3C, "A Well-Known URL for Changing Passwords").
  def change_password(conn, _params) do
    redirect(conn, to: ~p"/users/settings")
  end

  defp with_query(path, ""), do: path
  defp with_query(path, query), do: path <> "?" <> query
end
