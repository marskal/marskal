defmodule Marskal.Imports.TaskpaperTest do
  use ExUnit.Case, async: true

  alias Marskal.Imports.Taskpaper

  test "parses projects, tasks, notes, tags, and indents" do
    {items, skipped} =
      Taskpaper.parse("""
      Work: @flagged
      \t- Buy milk @errand @due(2026-10-21)
      \t\tThe note
      \t\t
      \t\tSecond line
      \t- email me@work.com
      \t    - Four spaces
      \t  - two spaces stay a note
      """)

    assert skipped == 0
    assert [work] = items
    assert work.type == :project
    assert work.text == "Work"
    assert work.tags == [{"flagged", nil}]

    assert [buy, email] = work.children
    assert buy.text == "Buy milk"
    assert buy.tags == [{"errand", nil}, {"due", "2026-10-21"}]
    assert buy.notes == "The note\n\nSecond line"
    assert email.text == "email me@work.com"
    assert email.tags == []
    assert [%{text: "Four spaces", depth: 2}] = email.children
    assert work.notes == "- two spaces stay a note"
  end

  test "keeps a colon in a project name and tags only after it" do
    {[project], 0} = Taskpaper.parse("Name: more: @done(2026-10-21)\n")
    assert project.text == "Name: more"
    assert project.tags == [{"done", "2026-10-21"}]

    {[project], 0} = Taskpaper.parse("Project @flagged:\n\t- Task\n")
    assert project.text == "Project @flagged"
    assert project.tags == []
    assert [%{text: "Task"}] = project.children
  end

  test "stores tag values raw and ignores an unclosed parenthesis" do
    {[task], 0} = Taskpaper.parse("- Call @tags(Errands\\, Phone) @due(nope\n")
    assert task.tags == [{"tags", "Errands\\, Phone"}]
    assert task.text == "Call @due(nope"
  end

  test "an @ that would read as a tag survives a dump and a parse" do
    item = %Taskpaper{
      type: :task,
      text: "Email @Anna about it",
      notes: "@bob first\nthen x@y.com",
      tags: [{"tags", ["Waiting", "A, B"]}]
    }

    dumped = Taskpaper.dump([item])
    assert dumped =~ "@tags(Waiting, A\\, B)"

    {[task], 0} = Taskpaper.parse(dumped)
    assert task.text == "Email @Anna about it"
    assert task.notes == "@bob first\nthen x@y.com"
    assert task.tags == [{"tags", "Waiting, A\\, B"}]

    {[project], 0} =
      Taskpaper.dump([%Taskpaper{type: :project, text: "Plan @home", notes: ""}])
      |> Taskpaper.parse()

    assert project.text == "Plan @home"
    assert project.tags == []
  end

  test "a leading backslash keeps a note that would be a task or a project" do
    {[task], 0} =
      Taskpaper.parse("""
      - Task
      \t\\- looks like a task
      \t\\Project:
      \tKeep this
      """)

    assert task.notes == "- looks like a task\nProject:\nKeep this"
  end

  test "an orphan note is counted and a file with neither task nor project is refused" do
    {items, skipped} = Taskpaper.parse("- Task\nLeft out\n")
    assert [%{text: "Task"}] = items
    assert skipped == 1

    assert_raise ArgumentError, ~r/not a TaskPaper outline/, fn ->
      Taskpaper.parse("just words\n")
    end

    assert_raise ArgumentError, "This file is not UTF-8 text.", fn ->
      Taskpaper.parse(<<0xFF, 0xFE>>)
    end
  end

  test "accepts a BOM and CRLF, and round-trips through dump" do
    text = "\uFEFFWork:\r\n\t- Task\r\n\t\tnote\r\n"
    {[work], 0} = Taskpaper.parse(text)
    assert work.text == "Work"
    assert [%{text: "Task", notes: "note"}] = work.children

    assert Taskpaper.outline?("- A task\n")
    assert Taskpaper.outline?(text)
    refute Taskpaper.outline?("hello\n")
    refute Taskpaper.outline?(<<0xFF>>)

    dumped = Taskpaper.dump(work.children)
    {[again], 0} = Taskpaper.parse(dumped)
    assert again.text == "Task"
    assert again.notes == "note"
  end
end
