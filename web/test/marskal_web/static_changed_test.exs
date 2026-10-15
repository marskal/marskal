defmodule MarskalWeb.StaticChangedTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket

  # What phx.digest leaves for the latest deploy.
  defmodule Endpoint do
    def config(:cache_static_manifest_latest),
      do: %{"assets/css/app.css" => "assets/css/app-0f1e2d.css"}
  end

  test "a page with the latest assets hears nothing" do
    socket = socket(["/assets/css/app-0f1e2d.css?vsn=d"])

    assert {:cont, %Socket{} = socket} =
             MarskalWeb.StaticChanged.on_mount(:default, %{}, %{}, socket)

    assert pushed(socket) == []
  end

  test "a page from before the deploy is told to reload" do
    socket = socket(["/assets/css/app-9a8b7c.css?vsn=d"])
    {:cont, socket} = MarskalWeb.StaticChanged.on_mount(:default, %{}, %{}, socket)
    assert pushed(socket) == [["static-changed", %{}]]
  end

  defp socket(statics) do
    %Socket{
      endpoint: Endpoint,
      transport_pid: self(),
      private: %{connect_params: %{"_track_static" => statics}, live_temp: %{}}
    }
  end

  defp pushed(socket), do: Map.get(socket.private.live_temp, :push_events, [])
end
