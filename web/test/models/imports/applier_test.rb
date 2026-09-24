# frozen_string_literal: true

require "test_helper"
require "test_helpers/omnifocus_backup"

class Imports::ApplierTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @batch = @user.import_batches.new(source: "omnifocus", channel: :file, status: :pending)
    @batch.payload.attach(
      io: StringIO.new(OmnifocusBackup.compact_backup),
      filename: "OmniFocus.ofocus-backup",
      content_type: "application/zip"
    )
    @batch.save!
  end

  test "creates folders projects and tasks for the user" do
    Imports::Parser.call(@batch)
    assert @batch.reload.previewed?

    Imports::Applier.call(@batch)
    assert @batch.reload.applied?

    work = @batch.import_items.find_by!(source_id: "folderWork00").project_folder
    assert_equal "Work", work.name
    dropped = @batch.import_items.find_by!(source_id: "folderOld000").project_folder
    assert dropped.dropped?

    project = @batch.import_items.find_by!(source_id: "projSite0000").project
    assert_equal "Launch website", project.title
    assert_equal work, project.project_folder
    assert project.to_do?

    draft = @batch.import_items.find_by!(source_id: "taskDraft000").task
    assert_not draft.inbox?
    assert_equal project, draft.project
    assert draft.to_do?

    milk = @batch.import_items.find_by!(source_id: "taskInbox000").task
    assert milk.inbox?
    assert_nil milk.project

    done = @batch.import_items.find_by!(source_id: "taskDone0000").task
    assert done.done?
  end

  test "second import skips existing source ids" do
    Imports::Parser.call(@batch)
    Imports::Applier.call(@batch)
    created = @batch.import_items.task.count

    batch2 = @user.import_batches.new(source: "omnifocus", channel: :file, status: :pending)
    batch2.payload.attach(
      io: StringIO.new(OmnifocusBackup.compact_backup),
      filename: "OmniFocus.ofocus-backup",
      content_type: "application/zip"
    )
    batch2.save!
    Imports::Parser.call(batch2)
    Imports::Applier.call(batch2)

    assert_equal created, @user.import_items.task.count
    assert_equal 0, batch2.reload.stats.dig("created", "tasks")
    assert_operator batch2.stats.dig("skipped", "tasks"), :>, 0
  end

  test "applies an OmniFocus 4.9 tutorial backup" do
    batch = @user.import_batches.new(source: "omnifocus", channel: :file, status: :pending)
    batch.payload.attach(
      io: StringIO.new(OmnifocusBackup.tutorial_backup),
      filename: "omnifocus-tutorial.ofocus-backup.zip",
      content_type: "application/zip"
    )
    batch.save!

    Imports::Parser.call(batch)
    assert batch.reload.previewed?
    assert_equal 2, batch.stats["projects"]
    assert_operator batch.stats["tasks"], :>=, 20

    Imports::Applier.call(batch)
    assert batch.reload.applied?

    tutorial = @user.projects.find_by(title: "Get to know OmniFocus 4 for Mac")
    assert tutorial
    assert_includes tutorial.open_tasks.map(&:title), "Click this action"

    brokka = @user.projects.find_by(title: "Brokkassen")
    assert_equal [ "Gør noget", "Gør noget andet" ].sort, brokka.open_tasks.map(&:title).sort

    done = @user.tasks.find_by(title: "Create a project")
    assert done.done?
  end

  test "does not import into another user" do
    Imports::Parser.call(@batch)
    Imports::Applier.call(@batch)

    other = users(:two)
    assert_equal 0, other.tasks.where(title: "Buy milk").count
    assert_equal 0, other.projects.where(title: "Launch website").count
  end
end
