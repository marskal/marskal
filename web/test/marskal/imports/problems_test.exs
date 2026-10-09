defmodule Marskal.Imports.ProblemsTest do
  use ExUnit.Case, async: true

  alias Marskal.Imports.Graph
  alias Marskal.Imports.Problems
  alias Marskal.Imports.TagNode
  alias Marskal.Imports.TaskNode
  alias Marskal.Tasks.Task

  test "a graph without problems is left as it is" do
    graph = %Graph{tasks: [%TaskNode{source_id: "t", title: "Milk", notes: "Two"}]}

    assert Problems.mark(graph, "Todoist") == graph
  end

  test "a problem adds its tag, under Import problems, and a line in the notes" do
    graph = %Graph{
      tags: [%TagNode{source_id: "food", name: "Food", rank: 4}],
      tasks: [
        %TaskNode{
          source_id: "t",
          title: "Milk",
          notes: "Two litres",
          tag_source_ids: ["food"],
          problems: [{:missing_recurrence, "Repeat", "every\nmonday"}]
        }
      ]
    }

    %Graph{tasks: [task], tags: [_food, parent, child]} = Problems.mark(graph, "Todoist")

    assert task.notes == "Two litres\n\n---\nImported from Todoist:\n- Repeat: every monday"
    assert task.tag_source_ids == ["food", "problem:missing-recurrence"]
    assert %TagNode{source_id: "problem", name: "Import problems", rank: 5} = parent
    assert %TagNode{name: "Missing repeat", parent_source_id: "problem"} = child
  end

  test "a long title is cut, and the rest goes in the notes" do
    title = String.duplicate("a", Task.title_max()) <> " and more"
    graph = %Graph{tasks: [%TaskNode{source_id: "t", title: title}]}

    %Graph{tasks: [task]} = Problems.mark(graph, "OmniFocus")

    assert task.title == String.duplicate("a", Task.title_max())
    assert task.notes == "---\nImported from OmniFocus:\n- Title continued: and more"
    assert task.tag_source_ids == ["problem:shortened-title"]
  end

  test "notes too long are cut, and the block always fits" do
    long = String.duplicate("n", Task.notes_max() + 10)

    %Graph{tasks: [plain]} =
      Problems.mark(%Graph{tasks: [%TaskNode{source_id: "t", title: "A", notes: long}]}, "X")

    assert String.length(plain.notes) == Task.notes_max()
    assert plain.tag_source_ids == ["problem:shortened-notes"]

    node = %TaskNode{
      source_id: "t",
      title: "A",
      notes: long,
      problems: [{:missing_section, "Section", "Groceries"}]
    }

    %Graph{tasks: [task]} = Problems.mark(%Graph{tasks: [node]}, "Todoist")

    assert String.length(task.notes) == Task.notes_max()
    assert String.ends_with?(task.notes, "\n\n---\nImported from Todoist:\n- Section: Groceries")
    assert task.tag_source_ids == ["problem:missing-section", "problem:shortened-notes"]
  end
end
