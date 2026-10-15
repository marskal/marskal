defmodule MarskalWeb.ThemeToggleTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  test "the header offers light, dark, and automatic", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/open")

    for theme <- ~w(light dark auto) do
      assert has_element?(view, "#theme-toggle button[data-theme-choice='#{theme}']")
    end
  end

  test "the script that applies a saved theme before paint carries the CSP nonce", %{conn: conn} do
    conn = get(conn, ~p"/open")
    [policy] = get_resp_header(conn, "content-security-policy")
    [_, nonce] = Regex.run(~r/'nonce-([^']+)'/, policy)

    script =
      conn
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("head script[nonce='#{nonce}']")

    assert LazyHTML.text(script) =~ "marskal:theme"
  end
end
