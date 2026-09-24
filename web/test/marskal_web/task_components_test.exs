defmodule MarskalWeb.TaskComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Marskal.Tasks.Task

  test "a to-do row checks off to complete and still offers drop" do
    html = render_row(%Task{id: id(), title: "Milk", state: :to_do, notes: nil})

    assert html =~ "Milk"
    assert html =~ "aria-label=\"Mark as done\""
    assert html =~ "check__idle"
    assert html =~ "check__hint"
    assert html =~ "Drop"
    refute html =~ ">Done<"
  end

  test "a done row shows a completed check that reopens" do
    html = render_row(%Task{id: id(), title: "Milk", state: :done, notes: nil})

    assert html =~ "check check--done"
    assert html =~ "aria-label=\"Reopen\""
    assert html =~ "check__complete"
    refute html =~ "check__idle"
    refute html =~ "check__hint"
    refute html =~ "Drop"
  end

  test "a dropped row shows a crossed square that reopens" do
    html = render_row(%Task{id: id(), title: "Milk", state: :dropped, notes: nil})

    assert html =~ "check check--dropped"
    assert html =~ "aria-label=\"Reopen\""
    assert html =~ "check__dropped"
    refute html =~ "check__idle"
  end

  defp render_row(task) do
    render_component(&MarskalWeb.TaskComponents.list/1, %{
      id: "tasks",
      tasks: [task],
      empty: "None",
      actions: [:complete, :drop]
    })
  end

  defp id, do: "11111111-1111-7111-8111-111111111111"
end
