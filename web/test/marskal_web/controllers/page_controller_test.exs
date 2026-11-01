defmodule MarskalWeb.PageControllerTest do
  use MarskalWeb.ConnCase

  alias Marskal.Accounts

  import Marskal.AccountsFixtures

  test "pages link the web app manifest, which names its icons", %{conn: conn} do
    html = conn |> get(~p"/users/log-in") |> html_response(200)
    assert html =~ ~s|rel="manifest" href="/manifest.webmanifest"|

    conn = get(build_conn(), ~p"/manifest.webmanifest")
    assert response_content_type(conn, :json) =~ "application/manifest+json"
    manifest = Jason.decode!(response(conn, 200))
    assert manifest["display"] == "standalone"

    for %{"src" => src} <- manifest["icons"] do
      assert build_conn() |> get(src) |> response(200)
    end
  end

  test "GET / requires login", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  test "GET / opens the home view", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    assert redirected_to(get(conn, ~p"/")) == ~p"/open"

    for {home_view, path} <- [
          inbox: ~p"/inbox",
          open_tasks: ~p"/open",
          agenda: ~p"/agenda",
          flagged: ~p"/flagged"
        ] do
      {:ok, _} =
        Accounts.update_preferences(user, %{home_view: home_view}, Ecto.UUID.generate(version: 7))

      assert redirected_to(get(conn, ~p"/")) == path
    end
  end

  test "GET / keeps a query on that view", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    assert redirected_to(get(conn, ~p"/?task=abc")) == "/open?task=abc"

    {:ok, _} =
      Accounts.update_preferences(user, %{home_view: :agenda}, Ecto.UUID.generate(version: 7))

    assert redirected_to(get(conn, ~p"/?task=abc")) == "/agenda?task=abc"
  end

  test "the well-known change-password URL leads to settings", %{conn: conn} do
    assert redirected_to(get(conn, "/.well-known/change-password")) == ~p"/users/settings"

    # Password managers trust it only when other well-known paths are not found.
    conn =
      get(
        build_conn(),
        "/.well-known/resource-that-should-not-exist-whose-status-code-should-not-be-200"
      )

    assert conn.status == 404
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
