require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "root shows open tasks stream" do
    get root_path

    assert_response :success
    assert_select "h1", "Open tasks"
    assert_match "Write Phase 1 tests", response.body
    assert_match "Draft homepage copy", response.body
    assert_match "Launch website", response.body
    assert_no_match "Buy milk", response.body
    assert_no_match "Secret task", response.body
  end

  test "inbox shows only current user inbox to-dos" do
    get inbox_path

    assert_response :success
    assert_select "h1", "Inbox"
    assert_match "Buy milk", response.body
    assert_no_match "Write Phase 1 tests", response.body
    assert_no_match "Secret task", response.body
  end

  test "add creates inbox task" do
    assert_difference -> { @user.tasks.count }, 1 do
      post tasks_path, params: { task: { title: "Call dentist", notes: "Morning" } }
    end

    task = @user.tasks.find_by!(title: "Call dentist")
    assert task.inbox?
    assert task.to_do?
    assert_equal "Morning", task.notes
    assert_redirected_to inbox_path
  end

  test "add requires title" do
    assert_no_difference -> { @user.tasks.count } do
      post tasks_path, params: { task: { title: "" } }
    end

    assert_response :redirect
    follow_redirect!
    assert_match(/could not add|blank/i, flash[:alert].to_s + response.body)
  end

  test "add under project skips inbox" do
    project = projects(:website)

    assert_difference -> { @user.tasks.count }, 1 do
      post tasks_path, params: { task: { title: "Pick hosting", project_id: project.id } }
    end

    task = @user.tasks.find_by!(title: "Pick hosting")
    assert_equal project, task.project
    assert_not task.inbox?
    assert task.to_do?
    assert_redirected_to project_path(project)
  end

  test "cannot assign task to another users project" do
    other_project = projects(:other_user_project)

    assert_no_difference -> { @user.tasks.count } do
      post tasks_path, params: { task: { title: "Nope", project_id: other_project.id } }
    end

    assert_response :redirect
  end

  test "move_to_open leaves inbox" do
    task = tasks(:inbox_one)

    patch move_to_open_task_path(task)

    assert_not task.reload.inbox?
    assert_redirected_to inbox_path
  end

  test "complete marks done" do
    task = tasks(:open_one)

    patch complete_task_path(task)

    assert task.reload.done?
    assert_redirected_to root_path
  end

  test "drop marks dropped" do
    task = tasks(:open_one)

    patch drop_task_path(task)

    assert task.reload.dropped?
  end

  test "reopen restores to_do" do
    task = tasks(:done_one)

    patch reopen_task_path(task)

    assert task.reload.to_do?
  end

  test "cannot act on another users task" do
    task = tasks(:other_user_task)

    patch complete_task_path(task)
    assert_response :not_found

    patch move_to_open_task_path(task)
    assert_response :not_found
  end

  test "requires authentication" do
    sign_out

    get root_path
    assert_redirected_to new_session_path

    get inbox_path
    assert_redirected_to new_session_path
  end
end
