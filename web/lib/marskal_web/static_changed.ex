defmodule MarskalWeb.StaticChanged do
  @moduledoc """
  Tells a page left open across a deploy that it should be reloaded.

  Such a tab keeps the CSS and JS it loaded, but its LiveView reconnects
  to the new server and renders the new markup, so styles go wrong. The
  root layout tracks its assets (`phx-track-static`); when a reconnecting
  page's differ from the server's, this pushes `static-changed`, and
  `app.ts` shows the banner the root layout holds.
  """

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) and static_changed?(socket),
      do: {:cont, push_event(socket, "static-changed", %{})},
      else: {:cont, socket}
  end
end
