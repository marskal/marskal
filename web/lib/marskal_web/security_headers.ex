defmodule MarskalWeb.SecurityHeaders do
  @moduledoc """
  The response headers of the OWASP HTTP Headers Cheat Sheet, on every
  page and API response. HSTS comes from `force_ssl` in `config/prod.exs`.

  Scripts and stylesheets load only from this origin, or inline with the
  per-request nonce in `conn.assigns.csp_nonce` (LiveDashboard needs it).
  `style` attributes are allowed: outline depth is a custom property set in
  markup, and LiveView patches attributes.

  The policy has no `form-action`: Chrome applies it to the redirects after a
  form post, and signing in for an OAuth client posts the log-in form and
  then follows Hydra to that client's redirect URI.

  In development the live reload frame is served before this plug.
  `MarskalWeb.LiveReloadFrame` puts this embedder policy on that response,
  which is what lets the browser show the frame.
  """

  import Plug.Conn

  @headers [
    {"cache-control", "no-store"},
    {"cross-origin-embedder-policy", "require-corp"},
    {"cross-origin-opener-policy", "same-origin"},
    {"cross-origin-resource-policy", "same-site"},
    {"permissions-policy", "camera=(), geolocation=(), microphone=()"},
    {"referrer-policy", "strict-origin-when-cross-origin"},
    {"x-content-type-options", "nosniff"},
    {"x-dns-prefetch-control", "off"},
    {"x-frame-options", "DENY"},
    {"x-permitted-cross-domain-policies", "none"},
    {"x-robots-tag", "noindex, nofollow"}
  ]

  @doc "Headers for static files, which `Plug.Static` serves before the router."
  def static_headers do
    %{"x-content-type-options" => "nosniff", "cross-origin-resource-policy" => "same-site"}
  end

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.encode64()

    conn
    |> assign(:csp_nonce, nonce)
    |> merge_resp_headers([{"content-security-policy", policy(nonce)} | @headers])
  end

  defp policy(nonce) do
    Enum.join(
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{nonce}'",
        "style-src 'self' 'nonce-#{nonce}'",
        "style-src-attr 'unsafe-inline'",
        "object-src 'none'",
        "base-uri 'self'",
        "frame-ancestors 'none'"
      ],
      "; "
    )
  end
end
