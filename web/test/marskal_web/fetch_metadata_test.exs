defmodule MarskalWeb.FetchMetadataTest do
  use MarskalWeb.ConnCase, async: true

  @login %{"user" => %{"email" => "nobody@marskal.example", "password" => "wrong"}}

  defp fetch(conn, method, path, headers) do
    conn
    |> Map.put(:host, "marskal.example")
    |> then(&Enum.reduce(headers, &1, fn {k, v}, c -> put_req_header(c, k, v) end))
    |> dispatch(@endpoint, method, path, @login)
  end

  defp refused?(conn), do: conn.status == 403 and conn.resp_body == "Cross-site request refused"

  for site <- ~w(same-origin same-site none) do
    test "a #{site} POST passes", %{conn: conn} do
      conn = fetch(conn, :post, ~p"/users/log-in", [{"sec-fetch-site", unquote(site)}])
      refute refused?(conn)
    end
  end

  test "a cross-site link to a page passes", %{conn: conn} do
    conn =
      fetch(conn, :get, ~p"/users/log-in", [
        {"sec-fetch-site", "cross-site"},
        {"sec-fetch-mode", "navigate"},
        {"sec-fetch-dest", "document"}
      ])

    assert conn.status == 200
  end

  test "a cross-site POST is refused", %{conn: conn} do
    conn =
      fetch(conn, :post, ~p"/users/log-in", [
        {"sec-fetch-site", "cross-site"},
        {"sec-fetch-mode", "navigate"},
        {"sec-fetch-dest", "document"}
      ])

    assert refused?(conn)
    assert get_resp_header(conn, "x-frame-options") == ["DENY"]
  end

  test "a cross-site fetch or embed is refused", %{conn: conn} do
    for {mode, dest} <- [{"cors", "empty"}, {"no-cors", "script"}, {"navigate", "iframe"}] do
      conn =
        fetch(conn, :get, ~p"/users/log-in", [
          {"sec-fetch-site", "cross-site"},
          {"sec-fetch-mode", mode},
          {"sec-fetch-dest", dest}
        ])

      assert refused?(conn), "#{mode} #{dest}"
    end
  end

  test "an unknown Sec-Fetch-Site is refused", %{conn: conn} do
    assert refused?(fetch(conn, :get, ~p"/users/log-in", [{"sec-fetch-site", "bogus"}]))
  end

  describe "without Sec-Fetch-Site" do
    test "a POST from this host passes", %{conn: conn} do
      conn = fetch(conn, :post, ~p"/users/log-in", [{"origin", "https://marskal.example"}])
      refute refused?(conn)
    end

    test "a POST from another host is refused", %{conn: conn} do
      assert refused?(fetch(conn, :post, ~p"/users/log-in", [{"origin", "https://evil.example"}]))
      assert refused?(fetch(conn, :post, ~p"/users/log-in", [{"origin", "null"}]))

      assert refused?(
               fetch(conn, :post, ~p"/users/log-in", [{"referer", "https://evil.example/x"}])
             )
    end

    test "a GET from another host passes", %{conn: conn} do
      conn = fetch(conn, :get, ~p"/users/log-in", [{"referer", "https://evil.example/x"}])
      assert conn.status == 200
    end

    test "a POST with neither Origin nor Referer passes", %{conn: conn} do
      refute refused?(fetch(conn, :post, ~p"/users/log-in", []))
    end
  end

  test "the sync API is not checked", %{conn: conn} do
    conn = fetch(conn, :post, ~p"/api/v1/sync/push", [{"sec-fetch-site", "cross-site"}])
    assert conn.status == 401
  end
end
