defmodule Marskal.Imports.OmnifocusAdapterTest do
  use ExUnit.Case, async: true

  alias Marskal.Imports.Limits
  alias Marskal.Imports.OmnifocusAdapter

  test "sniffs ofocus-backup names" do
    assert OmnifocusAdapter.match?("not a zip", "OmniFocus.ofocus-backup")
  end

  test "rejects a random zip" do
    bytes = OmnifocusBackup.zip([{"readme.txt", "hello"}])
    refute OmnifocusAdapter.match?(bytes, "notes.zip")
  end

  test "parses folders projects inbox and completed actions" do
    graph = OmnifocusAdapter.parse(OmnifocusBackup.compact_backup(), filename: "x.ofocus-backup")

    assert graph.source == "omnifocus"
    assert Enum.sort(Enum.map(graph.folders, & &1.name)) == ["Old stuff", "Work"]
    assert Enum.find(graph.folders, &(&1.name == "Old stuff")).dropped
    assert Enum.map(graph.projects, & &1.title) == ["Launch website"]
    assert hd(graph.projects).folder_source_id == "folderWork00"

    titles = Enum.map(graph.tasks, & &1.title)
    assert "Draft homepage" in titles
    assert "Pick palette" in titles
    assert "Buy milk" in titles

    milk = Enum.find(graph.tasks, &(&1.title == "Buy milk"))
    assert milk.inbox
    assert milk.project_source_id == nil

    draft = Enum.find(graph.tasks, &(&1.title == "Draft homepage"))
    refute draft.inbox
    assert draft.project_source_id == "projSite0000"
    assert draft.state == "to_do"

    done = Enum.find(graph.tasks, &(&1.title == "Pick palette"))
    assert done.state == "done"
  end

  test "parses an OmniFocus 4.9 tutorial package zip" do
    graph =
      OmnifocusAdapter.parse(
        OmnifocusBackup.tutorial_backup(),
        filename: "omnifocus-tutorial.ofocus-backup.zip"
      )

    assert graph.source == "omnifocus"
    assert graph.folders == []
    titles = Enum.map(graph.projects, & &1.title)
    assert "Get to know OmniFocus 4 for Mac" in titles
    assert "Brokkassen" in titles
    assert length(graph.projects) == 2

    task_titles = Enum.map(graph.tasks, & &1.title)
    assert "Click this action" in task_titles
    assert "Gør noget" in task_titles
    assert "Create a project" in task_titles
    refute Enum.any?(graph.tasks, & &1.inbox)

    click = Enum.find(graph.tasks, &(&1.title == "Click this action"))
    tutorial = Enum.find(graph.projects, &(&1.title == "Get to know OmniFocus 4 for Mac"))
    assert click.project_source_id == tutorial.source_id
    assert click.state == "to_do"

    done = Enum.find(graph.tasks, &(&1.title == "Create a project"))
    assert done.state == "done"

    brokka = Enum.find(graph.projects, &(&1.title == "Brokkassen"))
    noget = Enum.find(graph.tasks, &(&1.title == "Gør noget"))
    assert noget.project_source_id == brokka.source_id

    inspector = Enum.find(graph.tasks, &(&1.title == "Check out the Inspector"))
    assert inspector.notes =~ "Click the Inspect button"
    assert inspector.notes =~ "](https://www.omnigroup.com/forward/of4-inspector)"
    refute inspector.notes =~ "AppleSystemUIFont"
  end

  test "rejects zip-slip entries" do
    assert_raise ArgumentError, fn ->
      OmnifocusAdapter.parse(OmnifocusBackup.zip_slip_archive(), filename: "x.ofocus-backup")
    end
  end

  test "does not expand external XML entities" do
    xml = """
    <?xml version="1.0"?>
    <!DOCTYPE omnifocus [
      <!ENTITY xxe SYSTEM "file:///etc/passwd">
    ]>
    <omnifocus xmlns="http://www.omnigroup.com/namespace/OmniFocus/v2">
      <task id="taskEvil0000"><name>&xxe;</name><inbox/></task>
    </omnifocus>
    """

    graph = OmnifocusAdapter.parse(OmnifocusBackup.zip_with_xml(xml), filename: "x.ofocus-backup")
    name = graph.tasks |> List.first() |> then(fn task -> task && task.title end) |> to_string()
    refute name =~ ~r/root:|passwd/
  end

  test "rejects oversized inflated XML" do
    limits = %Limits{xml_bytes: 2048, entry_bytes: 2048}
    xml = "<omnifocus>#{String.duplicate("a", 4096)}</omnifocus>"

    assert_raise ArgumentError, fn ->
      OmnifocusAdapter.parse(OmnifocusBackup.zip_with_xml(xml),
        filename: "x.ofocus-backup",
        limits: limits
      )
    end
  end
end
