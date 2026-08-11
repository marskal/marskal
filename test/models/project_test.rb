require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "defaults to to_do" do
    project = @user.projects.create!(title: "New project")

    assert project.to_do?
  end

  test "requires title" do
    project = @user.projects.new(title: "")

    assert_not project.valid?
    assert_includes project.errors[:title], "can't be blank"
  end

  test "open_stream excludes done and dropped" do
    open_ids = Project.open_stream.pluck(:id)

    assert_includes open_ids, projects(:website).id
    assert_not_includes open_ids, projects(:done_project).id
  end

  test "nullifies tasks when destroyed" do
    task = tasks(:project_task)
    project = projects(:website)

    project.destroy!

    assert_nil task.reload.project_id
  end

  test "complete and drop set terminal states" do
    project = projects(:website)

    project.complete!
    assert project.reload.done?

    project.reopen!
    assert project.reload.to_do?

    project.drop!
    assert project.reload.dropped?
  end

  test "can file in own folder" do
    project = projects(:unfiled_project)
    folder = project_folders(:work)

    project.update!(project_folder: folder)

    assert_equal folder, project.reload.project_folder
  end

  test "rejects folder owned by another user" do
    project = projects(:unfiled_project)
    project.project_folder = project_folders(:other_user_folder)

    assert_not project.valid?
    assert project.errors[:project_folder].any?
  end
end

