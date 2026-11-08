defmodule MarskalWeb.LiveReloadFrameTest do
  use MarskalWeb.ConnCase, async: true

  test "the live reload frame reciprocates the embedder policy" do
    conn = respond("/phoenix/live_reload/frame")

    assert get_resp_header(conn, "cross-origin-embedder-policy") == ["require-corp"]
    assert get_resp_header(conn, "x-frame-options") == []
    assert get_resp_header(conn, "content-security-policy") == []
  end

  test "a suffixed frame path gets the same header" do
    conn = respond("/phoenix/live_reload/frame/proxied")

    assert get_resp_header(conn, "cross-origin-embedder-policy") == ["require-corp"]
  end

  test "other responses are left alone" do
    conn = respond("/open")

    assert get_resp_header(conn, "cross-origin-embedder-policy") == []
  end

  defp respond(path) do
    build_conn(:get, path)
    |> MarskalWeb.LiveReloadFrame.call([])
    |> send_resp(200, "")
  end
end
