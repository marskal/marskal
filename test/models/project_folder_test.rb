require "test_helper"

class ProjectFolderTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "defaults to active with empty parent_path at root" do
    folder = @user.project_folders.create!(name: "Home")

    assert folder.active?
    assert_equal [], folder.parent_path
  end

  test "nested folder sets parent_path from parent" do
    folder = @user.project_folders.create!(name: "Nested", parent: project_folders(:work))

    assert_equal [ "Work" ], folder.parent_path
    assert_equal "Work / Nested", folder.breadcrumb_label
  end

  test "requires name" do
    folder = @user.project_folders.new(name: "")

    assert_not folder.valid?
    assert_includes folder.errors[:name], "can't be blank"
  end

  test "rejects parent owned by another user" do
    folder = @user.project_folders.new(name: "X", parent: project_folders(:other_user_folder))

    assert_not folder.valid?
    assert folder.errors[:parent].any?
  end

  test "rejects cyclic parent" do
    work = project_folders(:work)
    client = project_folders(:client_a)

    work.parent = client

    assert_not work.valid?
    assert_match(/cycle/i, work.errors[:parent].join)
  end

  test "rename cascades parent_path to descendants" do
    work = project_folders(:work)
    client = project_folders(:client_a)

    work.update!(name: "Career")

    assert_equal [ "Career" ], client.reload.parent_path
  end

  test "drop and activate" do
    folder = project_folders(:work)

    folder.drop!
    assert folder.reload.dropped?

    folder.activate!
    assert folder.reload.active?
  end

  test "nullifies projects when destroyed" do
    project = projects(:website)
    folder = project_folders(:client_a)

    folder.destroy!

    assert_nil project.reload.project_folder_id
  end
end
