defmodule Marskal.Imports.TaskpaperAdapterTest do
  use ExUnit.Case, async: true

  alias Marskal.Dates
  alias Marskal.Imports.Limits
  alias Marskal.Imports.TaskpaperAdapter

  test "sniffs a taskpaper name or an outline, and leaves a zip alone" do
    assert TaskpaperAdapter.match?("hello", "Export.taskpaper")
    assert TaskpaperAdapter.match?("- A task\n", "notes.txt")
    refute TaskpaperAdapter.match?("not an outline\n", "notes.txt")
    refute TaskpaperAdapter.match?(<<0x50, 0x4B, 0x03, 0x04>>, "archive.zip")
  end

  test "a line without @id keeps its identity when another line is added" do
    ids = fn text ->
      text |> TaskpaperAdapter.parse() |> Map.fetch!(:tasks) |> Map.new(&{&1.title, &1.source_id})
    end

    before = ids.("Work:\n\t- A\n\t- B\n\t- A\n")
    later = ids.("Work:\n\t- New\n\t- A\n\t- B\n\t- A\n")

    assert Map.take(later, ["A", "B"]) == Map.take(before, ["A", "B"])
    refute later["New"] in Map.values(before)

    graph = TaskpaperAdapter.parse("Work:\n\t- A\n\t- A\n")
    assert [_, _] = graph.tasks |> Enum.map(& &1.source_id) |> Enum.uniq()
  end

  test "inbox, no project, and Archive" do
    graph =
      TaskpaperAdapter.parse("""
      Inbox:
      \tKept aside
      \t- Captured
      Archive:
      \t- Old @done
      - Loose
      """)

    assert graph.source == "taskpaper"
    assert graph.folders == []
    assert [%{title: "Archive"}] = graph.projects
    assert [captured, old, loose] = graph.tasks
    assert captured.title == "Captured"
    assert captured.inbox
    refute captured.project_source_id
    assert old.title == "Old"
    assert old.state == "done"
    assert old.project_source_id == hd(graph.projects).source_id
    refute old.inbox
    assert loose.title == "Loose"
    refute loose.inbox
    refute loose.project_source_id
    assert graph.skipped_rows == 1
  end

  test "a folder by tag or by shape, and a nested project" do
    graph =
      TaskpaperAdapter.parse("""
      Bag: @folder
      \t- D
      \tKept:
      \t\t- C
      Area:
      \tOne:
      \t\t- A
      \tTwo:
      \t\t- B
      Outer:
      \t- task
      \tInner:
      \t\t- deep
      """)

    folders = Map.new(graph.folders, &{&1.name, &1})
    assert folders["Bag"]
    assert folders["Area"]
    refute Map.has_key?(folders, "Outer")

    projects = Map.new(graph.projects, &{&1.title, &1})
    assert projects["Kept"].folder_source_id == folders["Bag"].source_id
    assert projects["One"].folder_source_id == folders["Area"].source_id
    assert projects["Two"].folder_source_id == folders["Area"].source_id
    assert projects["Outer"].folder_source_id == nil

    inner = projects["Inner"]
    assert inner.folder_source_id == nil
    assert {:nested_project, "Nested project", "Outer"} in inner.problems

    tasks = Map.new(graph.tasks, &{&1.title, &1})
    assert tasks["D"].inbox
    refute tasks["D"].project_source_id
    assert tasks["C"].project_source_id == projects["Kept"].source_id
    refute tasks["C"].inbox
    assert tasks["deep"].project_source_id == inner.source_id
  end

  test "tags, dates, defer, a bad URL, and a repeat" do
    graph =
      TaskpaperAdapter.parse("""
      - Call @tags(Home : Errands, Phone) @today @priority(1)
      - Wait @defer
      - Also @defer()
      - Pay @due(2026-10-21 5pm) @planned(2026-10-21) @defer(2026-10-20 15:04)
      - Bad @url(javascript:alert\\(1\\))
      - Go @url(https://example.com/x)
      - Weekly @due(2026-10-21) @repeat-rule(FREQ=WEEKLY) @repeat-schedule-type(from-assigned) @repeat-anchor-date(dateDue)
      - Both @done @dropped(2026-10-21)
      """)

    tags = Map.new(graph.tags, &{&1.name, &1})
    assert tags["Home"].parent_source_id == nil
    assert tags["Errands"].parent_source_id == tags["Home"].source_id
    assert tags["Phone"]
    assert tags["today"]
    assert tags["priority"]

    call = task(graph, "Call")
    assert tags["Errands"].source_id in call.tag_source_ids
    assert tags["Phone"].source_id in call.tag_source_ids
    assert tags["today"].source_id in call.tag_source_ids
    assert tags["priority"].source_id in call.tag_source_ids
    refute tags["Home"].source_id in call.tag_source_ids

    assert task(graph, "Wait").deferred_indefinitely
    assert task(graph, "Also").deferred_indefinitely

    pay = task(graph, "Pay")
    assert pay.due == "2026-10-21T17:00:00"
    assert pay.planned == "2026-10-21"
    assert pay.defer_until == "2026-10-20T15:04:00"
    assert Dates.parse_source(pay.due, :due_at, "Etc/UTC")

    bad = task(graph, "Bad")
    assert bad.url == nil
    assert {:unread_value, "URL", "javascript:alert(1)"} in bad.problems

    assert task(graph, "Go").url == "https://example.com/x"

    weekly = task(graph, "Weekly")
    assert weekly.recurrence["frequency"] == "weeks"
    assert weekly.recurrence["mode"] == "regular"
    assert weekly.recurrence["anchor"] == "due"

    both = task(graph, "Both")
    assert both.state == "dropped"
    assert both.resolved_at == "2026-10-21"
  end

  test "an unreadable date is a problem and the item still comes in" do
    graph = TaskpaperAdapter.parse("- Later @due(sometime) @done(nope)\n")
    task = task(graph, "Later")
    assert task.state == "done"
    assert task.due == nil
    assert task.resolved_at == nil
    assert {:unread_value, "Due", "sometime"} in task.problems
    assert {:unread_value, "Done", "nope"} in task.problems
  end

  test "refuses an outline over the record limit" do
    assert_raise ArgumentError, "This outline has too many items.", fn ->
      TaskpaperAdapter.parse("- A\n- B\n", limits: %Limits{records: 1})
    end
  end

  defp task(graph, title), do: Enum.find(graph.tasks, &(&1.title == title))
end
