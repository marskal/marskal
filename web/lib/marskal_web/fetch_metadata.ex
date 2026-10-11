defmodule MarskalWeb.FetchMetadata do
  @moduledoc """
  Refuses cross-site requests to pages, from the browser's `Sec-Fetch-*`
  request headers (the OWASP CSRF Prevention Cheat Sheet). It adds to the
  CSRF token and `SameSite` cookie; it replaces neither.

  Requests from this site and ones the user starts (`none`) pass. From
  another site only a top-level GET passes: a link to the app, or Todoist
  sending the browser back after its OAuth. A browser that sends no
  `Sec-Fetch-Site` is held to `Origin`, else `Referer`, on unsafe methods.

  The sync API takes bearer tokens, not cookies, and does not use this.
  """

  import Plug.Conn

  @safe_methods ~w(GET HEAD)

  def init(opts), do: opts

  def call(conn, _opts) do
    if allowed?(conn), do: conn, else: refuse(conn)
  end

  defp allowed?(conn) do
    case get_req_header(conn, "sec-fetch-site") do
      [site] when site in ~w(same-origin same-site none) -> true
      ["cross-site"] -> navigation?(conn)
      [] -> conn.method in @safe_methods or same_host?(conn)
      _ -> false
    end
  end

  defp navigation?(conn) do
    conn.method in @safe_methods and
      get_req_header(conn, "sec-fetch-mode") == ["navigate"] and
      get_req_header(conn, "sec-fetch-dest") in [[], ["document"]]
  end

  defp same_host?(conn) do
    case get_req_header(conn, "origin") ++ get_req_header(conn, "referer") do
      [url | _] -> URI.parse(url).host == conn.host
      [] -> true
    end
  end

  defp refuse(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(403, "Cross-site request refused")
    |> halt()
  end
end
