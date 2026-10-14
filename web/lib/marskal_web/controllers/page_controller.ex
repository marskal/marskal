defmodule MarskalWeb.PageController do
  use MarskalWeb, :controller

  alias MarskalWeb.UserAuth

  # / opens the user's home view. With none set, the open tasks.
  # A query, such as ?task=, comes along.
  def home(conn, _params) do
    redirect(conn, to: with_query(UserAuth.signed_in_path(conn), conn.query_string))
  end

  defp with_query(path, ""), do: path
  defp with_query(path, query), do: path <> "?" <> query
end
