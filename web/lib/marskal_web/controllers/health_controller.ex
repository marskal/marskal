defmodule MarskalWeb.HealthController do
  use MarskalWeb, :controller

  def show(conn, _params) do
    send_resp(conn, 200, "ok")
  end
end
