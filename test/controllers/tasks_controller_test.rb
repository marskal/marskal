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

  test "open tasks render the inspector pane and select links" do
    get root_path

    assert_select "aside.app-inspector"
    assert_select "turbo-frame#task_inspector"
    assert_select "a.select[data-turbo-frame=task_inspector]", text: "Write Phase 1 tests"
    assert_select ".app-inspector__empty", text: /Select a task/
  end

  test "inbox and project pages render the inspector" do
    get inbox_path
    assert_select "aside.app-inspector"

    get project_path(projects(:website))
    assert_select "aside.app-inspector"
    assert_select "a.select[data-turbo-frame=task_inspector]", text: "Draft homepage copy"
  end

  test "projects index does not render the inspector" do
    get projects_path

    assert_select "aside.app-inspector", count: 0
  end

  test "task query param sets inspector frame src" do
    task = tasks(:open_one)

    get root_path(task: task.id)

    assert_select "turbo-frame#task_inspector[src*='#{task.id}']"
    assert_select "article.task-row.is-selected", text: /Write Phase 1 tests/
  end

  test "show in inspector frame renders all editable fields" do
    task = tasks(:open_one)

    get task_path(task, list_context: "open"), headers: { "Turbo-Frame" => "task_inspector" }

    assert_response :success
    assert_select "turbo-frame#task_inspector"
    assert_select ".task-inspector"
    assert_select "input[name='task[title]'][value=?]", task.title
    assert_select "textarea[name='task[notes]']"
    assert_select "select[name='task[project_id]']"
    assert_select "input[name='task[inbox]']"
    assert_select "select[name='task[state]']"
  end

  test "show without a turbo frame redirects to the task list with selection" do
    task = tasks(:open_one)

    get task_path(task)

    assert_redirected_to root_path(task: task.id)
  end

  test "inbox task show redirects to inbox with selection" do
    task = tasks(:inbox_one)

    get task_path(task)

    assert_redirected_to inbox_path(task: task.id)
  end

  test "cannot show another users task" do
    get task_path(tasks(:other_user_task)), headers: { "Turbo-Frame" => "task_inspector" }

    assert_response :not_found
  end

  test "update writes all task fields" do
    task = tasks(:open_one)
    project = projects(:website)

    patch task_path(task), params: {
      task: {
        title: "Clarify this",
        notes: "A note",
        project_id: project.id,
        inbox: "1",
        state: "dropped"
      }
    }

    task.reload
    assert_equal "Clarify this", task.title
    assert_equal "A note", task.notes
    assert_equal project.id, task.project_id
    assert task.inbox?
    assert task.dropped?
    assert_redirected_to inbox_path(task: task.id)
  end

  test "update can clear the project" do
    task = tasks(:project_task)

    patch task_path(task), params: { task: { project_id: "" } }

    assert_nil task.reload.project_id
    assert_redirected_to root_path(task: task.id)
  end

  test "update via turbo stream refreshes inspector and row" do
    task = tasks(:open_one)

    patch task_path(task),
          params: { task: { title: "Renamed open task" }, list_context: "open" },
          as: :turbo_stream

    assert_response :success
    assert_equal "Renamed open task", task.reload.title
    assert_match "task_inspector", response.body
    assert_match "Renamed open task", response.body
    assert_match "replace", response.body
  end

  test "update via turbo stream removes a row that left the current list" do
    task = tasks(:open_one)

    patch task_path(task),
          params: { task: { state: "done" }, list_context: "open" },
          as: :turbo_stream

    assert task.reload.done?
    assert_match(/turbo-stream[^>]*action="remove"/, response.body)
  end

  test "cannot update another users task" do
    patch task_path(tasks(:other_user_task)), params: { task: { title: "Hacked" } }

    assert_response :not_found
    assert_equal "Secret task", tasks(:other_user_task).reload.title
  end
end
