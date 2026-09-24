defmodule MarskalWeb.PageControllerTest do
  use MarskalWeb.ConnCase

  test "GET / requires login", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  test "GET /up is healthy", %{conn: conn} do
    conn = get(conn, ~p"/up")
    assert response(conn, 200) == "ok"
  end
end
