defmodule MarskalWeb.HealthControllerTest do
  use MarskalWeb.ConnCase, async: true

  import ExUnit.CaptureLog

  test "GET /up is ok when the database answers", %{conn: conn} do
    conn = get(conn, ~p"/up")

    assert response(conn, 200) == "ok"
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "HEAD /up is ok without a body", %{conn: conn} do
    conn = head(conn, ~p"/up")

    assert response(conn, 200) == ""
    assert get_resp_header(conn, "set-cookie") == []
  end

  # The sandbox lends its connection to the test process only. A plain spawn
  # has no caller chain, so the check cannot reach Postgres. Task would,
  # because it copies `$callers` and the sandbox allows those.
  test "GET /up is unavailable when the database check cannot run", %{conn: conn} do
    parent = self()

    log =
      capture_log(fn ->
        spawn(fn -> send(parent, {:health_conn, get(conn, ~p"/up")}) end)

        receive do
          {:health_conn, checked} -> send(parent, {:keep, checked})
        after
          5_000 -> flunk("health check did not return")
        end
      end)

    assert_received {:keep, checked}
    body = response(checked, 503)

    assert body == "unavailable"
    refute body =~ "SELECT"
    assert get_resp_header(checked, "cache-control") == ["no-store"]
    assert get_resp_header(checked, "set-cookie") == []
    assert log =~ "Health check failed"
  end
end
