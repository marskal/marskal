defmodule MarskalWeb.ColocatedCSS do
  @moduledoc false

  use Phoenix.LiveView.ColocatedCSS

  @impl true
  def transform("style", _attrs, css, _meta), do: {:ok, css, []}
end
