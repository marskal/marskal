defmodule MarskalWeb.ExportController do
  use MarskalWeb, :controller

  alias Marskal.Exports.Taskpaper

  def taskpaper(conn, _params) do
    user = conn.assigns.current_scope.user
    filename = Taskpaper.filename(user)

    conn
    |> put_resp_content_type("text/plain", "utf-8")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, Taskpaper.render(user))
  end
end
