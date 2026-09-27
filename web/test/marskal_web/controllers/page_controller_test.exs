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

  test "the header shows the app icon", %{conn: conn} do
    conn = get(conn, ~p"/users/log-in")
    html = html_response(conn, 200)

    assert html =~ ~s(class="app-header__logo")
    assert html =~ ~s(src="/images/icon.svg")
    assert html =~ ">Marskal<"
    assert html =~ ~s(rel="icon")
    assert html =~ ~s(href="/images/icon.svg")
    assert html =~ ~s(rel="apple-touch-icon")
    assert html =~ ~s(href="/images/icon.png")
  end

  test "icon files are served", %{conn: conn} do
    assert get(conn, ~p"/images/icon.svg").status == 200
    assert get(conn, ~p"/images/icon.png").status == 200
    assert get(conn, ~p"/favicon.ico").status == 200
  end
end
