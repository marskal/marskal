defmodule MarskalWeb.LucideTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "a Lucide icon renders an svg" do
    html = render_component(&Lucideicons.inbox/1, class: "icon")

    assert html =~ "<svg"
    assert html =~ "icon"
    assert html =~ "polyline"
  end

  test "an unknown icon name is rejected" do
    assert_raise RuntimeError, ~r/not found/, fn ->
      render_component(&Lucideicons.render!/1, name: "not-a-real-icon")
    end
  end
end
