defmodule Marskal.Imports.TodoistAdapterTest do
  use ExUnit.Case, async: true

  alias Marskal.Imports.Limits
  alias Marskal.Imports.TodoistAdapter

  test "maps a sync snapshot into folders, projects, tasks, and tags" do
    graph = TodoistAdapter.parse(TodoistSnapshot.json())

    assert graph.source == "todoist"
    assert Enum.map(graph.folders, & &1.name) == ["Work", "Launch"]
    assert Enum.map(graph.projects, & &1.title) == ["Launch tasks", "Archive", "Child", "Paused"]

    work = Enum.find(graph.folders, &(&1.name == "Work"))
    assert work.parent_source_id == nil

    launch_folder = Enum.find(graph.folders, &(&1.name == "Launch"))
    assert launch_folder.source_id == "folder:project:p1"
    assert launch_folder.parent_source_id == "folder:fold1"
    refute launch_folder.dropped

    launch = Enum.find(graph.projects, &(&1.title == "Launch tasks"))
    assert launch.source_id == "project:p1"
    assert launch.folder_source_id == "folder:project:p1"
    assert launch.notes == "Site"
    assert launch.state == "to_do"

    child = Enum.find(graph.projects, &(&1.title == "Child"))
    assert child.folder_source_id == "folder:project:p1"
    refute child.extras["parent_source_id"]

    paused = Enum.find(graph.projects, &(&1.title == "Paused"))
    assert paused.state == "to_do"
    assert paused.extras["defer"] == "indefinite"

    archive = Enum.find(graph.projects, &(&1.title == "Archive"))
    assert archive.state == "dropped"

    assert Enum.map(graph.tags, & &1.name) ==
             ["Food", "Errand", "Import problems", "Missing repeat rule", "Missing section"]

    assert Enum.map(graph.tags, & &1.source_id) ==
             [
               "tag:l1",
               "tag:shared:errand",
               "problem",
               "problem:missing-recurrence",
               "problem:missing-section"
             ]

    titles = Enum.map(graph.tasks, & &1.title)
    assert Enum.sort(titles) == ["Ask editor", "Buy milk", "Shipped", "Write copy"]
    refute "Deleted" in titles
    refute "Orphan" in titles

    milk = Enum.find(graph.tasks, &(&1.title == "Buy milk"))
    assert milk.inbox
    assert milk.project_source_id == nil
    assert milk.tag_source_ids == ["tag:l1", "tag:shared:errand", "problem:missing-recurrence"]

    assert milk.notes =~
             ~r"---\nImported from Todoist:\n- Repeat: every monday starting next week\z"

    assert milk.planned == "2026-09-28"
    assert milk.extras["repeat"] == "every monday starting next week"
    assert milk.due == "2026-10-01"
    assert milk.extras["priority"] == 4

    editor = Enum.find(graph.tasks, &(&1.title == "Ask editor"))
    assert editor.url == "https://chat.example/editor"
    assert milk.url == nil

    copy = Enum.find(graph.tasks, &(&1.title == "Write copy"))
    refute copy.inbox
    assert copy.project_source_id == "project:p1"
    assert copy.notes == "Home page\n\n---\nImported from Todoist:\n- Section: Now"
    assert "problem:missing-section" in copy.tag_source_ids
    assert copy.extras["section"] == "Now"

    ask = Enum.find(graph.tasks, &(&1.title == "Ask editor"))
    assert ask.parent_source_id == "task:t2"
    assert ask.extras["parent_source_id"] == "task:t2"

    shipped = Enum.find(graph.tasks, &(&1.title == "Shipped"))
    assert shipped.state == "done"
  end

  test "a parent with no tasks is only a folder" do
    graph =
      TodoistAdapter.parse(
        Jason.encode!(%{
          "projects" => [
            %{"id" => "a", "name" => "Area"},
            %{"id" => "b", "name" => "Empty parent", "parent_id" => "a"},
            %{"id" => "c", "name" => "Leaf", "parent_id" => "b"}
          ],
          "items" => [
            %{"id" => "t", "content" => "Do it", "project_id" => "c"}
          ]
        })
      )

    assert Enum.map(graph.folders, & &1.name) == ["Area", "Empty parent"]
    assert Enum.map(graph.projects, & &1.title) == ["Leaf"]

    empty = Enum.find(graph.folders, &(&1.name == "Empty parent"))
    assert empty.parent_source_id == "folder:project:a"
    assert empty.source_id == "folder:project:b"

    leaf = Enum.find(graph.projects, &(&1.title == "Leaf"))
    assert leaf.folder_source_id == "folder:project:b"

    task = Enum.find(graph.tasks, &(&1.title == "Do it"))
    assert task.project_source_id == "project:c"
  end

  test "a parent cycle is cut and a project below it stays in place" do
    graph =
      TodoistAdapter.parse(
        Jason.encode!(%{
          "projects" => [
            %{"id" => "a", "name" => "A", "parent_id" => "b"},
            %{"id" => "b", "name" => "B", "parent_id" => "a"},
            %{"id" => "c", "name" => "C", "parent_id" => "b"}
          ]
        })
      )

    folders = Map.new(graph.folders, &{&1.source_id, &1.parent_source_id})
    assert folders["folder:project:b"] == nil
    refute Map.has_key?(folders, "folder:project:a")
    assert Enum.find(graph.projects, &(&1.title == "C")).folder_source_id == "folder:project:b"
    assert Enum.find(graph.projects, &(&1.title == "A")).folder_source_id == "folder:project:b"
  end

  test "links in project names move to the URL, and to a folder's extras" do
    graph =
      TodoistAdapter.parse(
        Jason.encode!(%{
          "projects" => [
            %{"id" => "a", "name" => "[Area](https://a.example)"},
            %{
              "id" => "b",
              "name" => "[Site](https://b.example) and [docs](https://docs.example)",
              "description" => "Ship it",
              "parent_id" => "a"
            }
          ]
        })
      )

    assert [%{name: "Area", extras: %{"url" => "https://a.example"}}] = graph.folders
    assert [site] = graph.projects
    assert site.title == "Site and docs"
    assert site.url == "https://b.example"
    assert site.notes == "Ship it\n\n- [docs](https://docs.example)"
  end

  test "rejects a snapshot that is not JSON" do
    assert_raise ArgumentError, ~r/could not be read/, fn ->
      TodoistAdapter.parse("not json")
    end
  end

  test "rejects a snapshot over the record limit" do
    limit = %Limits{}.records
    items = for n <- 1..(limit + 1), do: %{"id" => n, "content" => "Task #{n}"}

    assert_raise ArgumentError, ~r/too many items/, fn ->
      TodoistAdapter.parse(Jason.encode!(%{"items" => items}))
    end
  end
end
