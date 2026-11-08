defmodule MarskalWeb.LiveReloadFrame do
  @moduledoc """
  Adds `Cross-Origin-Embedder-Policy: require-corp` to Phoenix's live
  reload frame.

  Pages send that policy (`MarskalWeb.SecurityHeaders`). Localhost is a
  secure context, so the browser enforces it: a framed document loads
  only when its own response sends `require-corp` too.
  `Phoenix.LiveReloader` writes the frame and sends no such header, and
  the browser blocks the frame. This plug runs ahead of it and adds the
  header as the response goes out. It is installed only while code
  reloading is on.

  The rest of `MarskalWeb.SecurityHeaders` stays off this response.
  `X-Frame-Options: DENY` and `frame-ancestors 'none'` would refuse the
  embed, and the frame's script is inline, with no nonce for a policy.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["phoenix", "live_reload", "frame" | _]} = conn, _opts) do
    register_before_send(conn, fn conn ->
      put_resp_header(conn, "cross-origin-embedder-policy", "require-corp")
    end)
  end

  def call(conn, _opts), do: conn
end
