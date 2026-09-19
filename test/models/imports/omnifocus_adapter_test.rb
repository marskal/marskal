# frozen_string_literal: true

require "test_helper"
require "test_helpers/omnifocus_backup"

class Imports::OmnifocusAdapterTest < ActiveSupport::TestCase
  test "sniffs ofocus-backup names" do
    io = StringIO.new("not a zip")
    assert Imports::OmnifocusAdapter.match?(io, filename: "OmniFocus.ofocus-backup")
  end

  test "rejects a random zip" do
    bytes = Zip::OutputStream.write_buffer do |zio|
      zio.put_next_entry("readme.txt")
      zio.write "hello"
    end.string
    refute Imports::OmnifocusAdapter.match?(StringIO.new(bytes), filename: "notes.zip")
  end

  test "parses folders projects inbox and completed actions" do
    graph = Imports::OmnifocusAdapter.parse(StringIO.new(OmnifocusBackup.compact_backup), filename: "x.ofocus-backup")

    assert_equal "omnifocus", graph.source
    assert_equal [ "Work", "Old stuff" ].sort, graph.folders.map(&:name).sort
    assert graph.folders.find { |f| f.name == "Old stuff" }.dropped
    assert_equal [ "Launch website" ], graph.projects.map(&:title)
    assert_equal "folderWork00", graph.projects.first.folder_source_id

    titles = graph.tasks.map(&:title)
    assert_includes titles, "Draft homepage"
    assert_includes titles, "Pick palette"
    assert_includes titles, "Buy milk"

    milk = graph.tasks.find { |t| t.title == "Buy milk" }
    assert milk.inbox
    assert_nil milk.project_source_id

    draft = graph.tasks.find { |t| t.title == "Draft homepage" }
    assert_not draft.inbox
    assert_equal "projSite0000", draft.project_source_id
    assert_equal "to_do", draft.state

    done = graph.tasks.find { |t| t.title == "Pick palette" }
    assert_equal "done", done.state
  end

  test "parses an OmniFocus 4.9 tutorial package zip" do
    graph = Imports::OmnifocusAdapter.parse(
      StringIO.new(OmnifocusBackup.tutorial_backup),
      filename: "omnifocus-tutorial.ofocus-backup.zip"
    )

    assert_equal "omnifocus", graph.source
    assert_empty graph.folders
    titles = graph.projects.map(&:title)
    assert_includes titles, "Get to know OmniFocus 4 for Mac"
    assert_includes titles, "Brokkassen"
    assert_equal 2, graph.projects.size

    task_titles = graph.tasks.map(&:title)
    assert_includes task_titles, "Click this action"
    assert_includes task_titles, "Gør noget"
    assert_includes task_titles, "Create a project"
    assert_not graph.tasks.any?(&:inbox)

    click = graph.tasks.find { |t| t.title == "Click this action" }
    tutorial = graph.projects.find { |p| p.title == "Get to know OmniFocus 4 for Mac" }
    assert_equal tutorial.source_id, click.project_source_id
    assert_equal "to_do", click.state

    done = graph.tasks.find { |t| t.title == "Create a project" }
    assert_equal "done", done.state

    brokka = graph.projects.find { |p| p.title == "Brokkassen" }
    noget = graph.tasks.find { |t| t.title == "Gør noget" }
    assert_equal brokka.source_id, noget.project_source_id
  end

  test "rejects zip-slip entries" do
    assert_raises(ArgumentError) do
      Imports::OmnifocusAdapter.parse(StringIO.new(OmnifocusBackup.zip_slip_archive), filename: "x.ofocus-backup")
    end
  end
end
