defmodule Marskal.Exports.TaskpaperTest do
  use Marskal.DataCase, async: true

  import Marskal.AccountsFixtures

  alias Marskal.Exports.Taskpaper
  alias Marskal.Imports.TaskpaperAdapter
  alias Marskal.ProjectFolders
  alias Marskal.Projects
  alias Marskal.Recurrence
  alias Marskal.Tags
  alias Marskal.Tasks

  test "writes the outline and reads it back" do
    user = user_fixture()
    other = user_fixture()
    command = fn -> Ecto.UUID.generate(version: 7) end

    {:ok, folder} = ProjectFolders.create_folder(user, %{"name" => "Area"}, command.())

    {:ok, project} =
      Projects.create_project(
        user,
        %{"title" => "Research", "project_folder_id" => folder.id, "notes" => "Project note"},
        command.()
      )

    {:ok, inherited} = Tags.create_tag(user, %{"name" => "Inherited"}, command.())
    {:ok, _} = Tags.tag_project(user, project.id, inherited.id, command.())
    {:ok, own} = Tags.create_tag(user, %{"name" => "Own"}, command.())

    {:ok, flagged} =
      Tasks.create_task(
        user,
        %{
          "title" => "Read this",
          "notes" => "line one\n- looks like a task",
          "url" => "https://example.com/read",
          "project_id" => project.id,
          "inbox" => false,
          "flagged" => true
        },
        command.()
      )

    {:ok, _} = Tags.tag_task(user, flagged.id, own.id, command.())

    {:ok, child} =
      Tasks.create_task(
        user,
        %{"title" => "Child", "parent_id" => flagged.id, "inbox" => false},
        command.()
      )

    {:ok, _} =
      Tasks.create_task(user, %{"title" => "Captured", "inbox" => true}, command.())

    {:ok, _} =
      Tasks.create_task(
        user,
        %{"title" => "Loose", "inbox" => false, "state" => "dropped"},
        command.()
      )

    {:ok, _} =
      Tasks.create_task(
        user,
        %{"title" => "Finished", "inbox" => false, "state" => "done"},
        command.()
      )

    {:ok, gone} =
      Tasks.create_task(user, %{"title" => "Gone", "inbox" => false}, command.())

    {:ok, _} = Tasks.delete_task(user, gone.id, command.())

    {:ok, _} =
      Tasks.create_task(other, %{"title" => "Someone else", "inbox" => false}, command.())

    text = Taskpaper.render(user)

    assert text =~ "Inbox:"
    assert text =~ "Area: @folder"
    assert text =~ "Research:"
    assert text =~ "\t\tProject note\n"
    assert text =~ "@flagged"
    assert text =~ "@url(https://example.com/read)"
    assert text =~ "@tags(Inherited)"
    task_line = text |> String.split("\n") |> Enum.find(&(&1 =~ "Read this"))
    assert task_line =~ "@tags(Own)"
    refute task_line =~ "Inherited"
    assert task_line =~ "\t- Read this"
    assert text =~ "\t\t\t- Child"
    assert text =~ "- Loose @dropped"
    assert text =~ "- Finished @done"
    refute text =~ "Gone"
    refute text =~ "Someone else"

    project_at = String.split(text, "Research:", parts: 2) |> Enum.at(1)
    assert project_at =~ "Read this"
    assert project_at =~ "Child"

    graph = TaskpaperAdapter.parse(text)
    assert Enum.map(graph.folders, & &1.name) == ["Area"]
    assert Enum.map(graph.projects, & &1.title) == ["Research"]
    titles = Enum.map(graph.tasks, & &1.title)
    assert "Captured" in titles
    assert "Read this" in titles
    assert "Child" in titles
    assert "Loose" in titles
    assert "Finished" in titles
    refute "Gone" in titles

    read = Enum.find(graph.tasks, &(&1.title == "Read this"))
    assert read.flagged
    assert read.url == "https://example.com/read"
    assert read.notes == "line one\n- looks like a task"
    child_node = Enum.find(graph.tasks, &(&1.title == "Child"))
    assert child_node.parent_source_id == read.source_id
    assert child.id
  end

  test "writes a weekly repeat on the open occurrence" do
    user = user_fixture()
    command = fn -> Ecto.UUID.generate(version: 7) end

    {:ok, task} =
      Tasks.create_task(
        user,
        %{"title" => "Weekly", "inbox" => false, "due_at" => ~U[2026-10-21 15:00:00Z]},
        command.()
      )

    {:ok, _} =
      Recurrence.repeat_task(
        user,
        task.id,
        %{"mode" => "regular", "anchor" => "due", "interval" => 1, "frequency" => "weeks"},
        command.()
      )

    text = Taskpaper.render(user)
    assert text =~ "FREQ=WEEKLY"
    assert text =~ "WKST=MO"
    assert text =~ "@repeat-schedule-type(from-assigned)"
    assert text =~ "@repeat-anchor-date(dateDue)"

    graph = TaskpaperAdapter.parse(text)
    weekly = Enum.find(graph.tasks, &(&1.title == "Weekly"))
    assert weekly.recurrence["frequency"] == "weeks"
  end

  test "several own tags, and an @ in a title, come back as they were" do
    user = user_fixture()
    command = fn -> Ecto.UUID.generate(version: 7) end

    {:ok, task} =
      Tasks.create_task(user, %{"title" => "Email @Anna", "inbox" => false}, command.())

    for name <- ["Waiting", "Errands"] do
      {:ok, tag} = Tags.create_tag(user, %{"name" => name}, command.())
      {:ok, _} = Tags.tag_task(user, task.id, tag.id, command.())
    end

    graph = user |> Taskpaper.render() |> TaskpaperAdapter.parse()
    [read] = graph.tasks
    assert read.title == "Email @Anna"
    assert graph.tags |> Enum.map(& &1.name) |> Enum.sort() == ["Errands", "Waiting"]
    assert [_, _] = read.tag_source_ids
  end

  test "leaves out a repeat the RRULE cannot say" do
    user = user_fixture()
    command = fn -> Ecto.UUID.generate(version: 7) end

    {:ok, task} =
      Tasks.create_task(
        user,
        %{"title" => "Monthly", "inbox" => false, "due_at" => ~U[2026-11-02 15:00:00Z]},
        command.()
      )

    {:ok, _} =
      Recurrence.repeat_task(
        user,
        task.id,
        %{
          "mode" => "regular",
          "anchor" => "due",
          "interval" => 1,
          "frequency" => "months",
          "on_days" => ["1:day", "1:monday"]
        },
        command.()
      )

    text = Taskpaper.render(user)
    assert text =~ "- Monthly"
    refute text =~ "@repeat-rule"
  end

  test "an empty account renders nothing and names the file for today" do
    user = user_fixture()
    assert Taskpaper.render(user) == ""
    assert Taskpaper.filename(user) =~ ~r/^marskal-\d{4}-\d{2}-\d{2}\.taskpaper$/
  end
end
