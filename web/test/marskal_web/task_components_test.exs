defmodule MarskalWeb.TaskComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Marskal.Tasks.Task

  test "a to-do row checks off to complete and does not offer drop" do
    html = render_row(%Task{id: id(), title: "Milk", state: :to_do, notes: nil})

    assert html =~ "Milk"
    assert html =~ "aria-label=\"Mark as done\""
    assert html =~ "check__idle"
    assert html =~ "check__hint"
    assert html =~ "phx-click=\"inspect\""
    refute html =~ "Drop"
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

  test "an inherited date shows, marked as coming from above" do
    due = ~U[2026-10-05 10:00:00Z]
    task = %Task{id: id(), title: "Milk", state: :to_do, notes: nil}

    dates = %{
      id() => %{defer_until: nil, deferred_indefinitely: false, planned_at: nil, due_at: due}
    }

    html = render_row(task, dates)

    assert html =~ "mark--due"
    assert html =~ "mark--inherited"
    assert html =~ "From the task or project above"

    own = render_row(%{task | due_at: due}, dates)
    assert own =~ "mark--due"
    refute own =~ "mark--inherited"
  end

  defp render_row(task, dates \\ %{}) do
    render_component(&MarskalWeb.TaskComponents.list/1, %{
      id: "tasks",
      tasks: [task],
      dates: dates,
      empty: "None",
      actions: [:complete, :drop]
    })
  end

  defp id, do: "11111111-1111-7111-8111-111111111111"
end
