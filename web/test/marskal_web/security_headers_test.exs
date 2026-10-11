defmodule MarskalWeb.SecurityHeadersTest do
  use MarskalWeb.ConnCase, async: true

  import Marskal.AccountsFixtures

  test "pages carry the OWASP headers", %{conn: conn} do
    conn = get(conn, ~p"/users/log-in")

    assert get_resp_header(conn, "x-frame-options") == ["DENY"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "cross-origin-opener-policy") == ["same-origin"]
    assert get_resp_header(conn, "cross-origin-embedder-policy") == ["require-corp"]
    assert get_resp_header(conn, "cross-origin-resource-policy") == ["same-site"]
    assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
    assert get_resp_header(conn, "x-dns-prefetch-control") == ["off"]
    assert [_] = get_resp_header(conn, "permissions-policy")
  end

  test "the policy allows this origin and the request's nonce", %{conn: conn} do
    conn = get(conn, ~p"/users/log-in")
    [policy] = get_resp_header(conn, "content-security-policy")
    nonce = conn.assigns.csp_nonce

    assert policy =~ "default-src 'self'"
    assert policy =~ "script-src 'self' 'nonce-#{nonce}'"
    assert policy =~ "frame-ancestors 'none'"
    refute policy =~ "form-action"
    refute get(build_conn(), ~p"/users/log-in").assigns.csp_nonce == nonce
  end

  test "the sync API carries them, even when it refuses", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/sync/pull")

    assert conn.status == 401
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert [_] = get_resp_header(conn, "content-security-policy")
  end

  test "static files are nosniff", %{conn: conn} do
    conn = get(conn, ~p"/images/icon.svg")
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "the dashboard's inline assets use the nonce", %{conn: conn} do
    user = user_fixture() |> Ecto.Changeset.change(superuser: true) |> Marskal.Repo.update!()
    conn = conn |> log_in_user(user) |> get(~p"/dev/dashboard/home")

    assert html_response(conn, 200) =~ ~s(nonce="#{conn.assigns.csp_nonce}")
  end
end
