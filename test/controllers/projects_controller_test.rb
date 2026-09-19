require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "index lists folders and unfiled projects only for current user" do
    get projects_path

    assert_response :success
    assert_select "h1", "Projects"
    assert_match "Work", response.body
    assert_select ".project-list", text: /Plan vacation/
    assert_select ".project-list .project-card", text: /Launch website/, count: 0
    assert_no_match "Finish onboarding", response.body
    assert_no_match "Secret project", response.body
    assert_no_match "Old stuff", response.body # dropped folder hidden
  end

  test "show lists project tasks" do
    project = projects(:website)

    get project_path(project)

    assert_response :success
    assert_match "Launch website", response.body
    assert_match "Draft homepage copy", response.body
    assert_no_match "Secret task", response.body
  end

  test "create project" do
    assert_difference -> { @user.projects.count }, 1 do
      post projects_path, params: { project: { title: "Tax return", notes: "2025" } }
    end

    project = @user.projects.find_by!(title: "Tax return")
    assert project.to_do?
    assert_redirected_to project_path(project)
  end

  test "create project in folder" do
    folder = project_folders(:client_a)

    assert_difference -> { @user.projects.count }, 1 do
      post projects_path, params: { project: { title: "Retainer", project_folder_id: folder.id } }
    end

    project = @user.projects.find_by!(title: "Retainer")
    assert_equal folder, project.project_folder
  end

  test "cannot file project in another users folder" do
    assert_no_difference -> { @user.projects.count } do
      post projects_path, params: {
        project: { title: "Nope", project_folder_id: project_folders(:other_user_folder).id }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create requires title" do
    assert_no_difference -> { @user.projects.count } do
      post projects_path, params: { project: { title: "" } }
    end

    assert_response :unprocessable_entity
  end

  test "complete marks project done" do
    project = projects(:website)

    patch complete_project_path(project)

    assert project.reload.done?
    assert_redirected_to projects_path
  end

  test "cannot access another users project" do
    project = projects(:other_user_project)

    get project_path(project)
    assert_response :not_found

    patch complete_project_path(project)
    assert_response :not_found
  end

  test "requires authentication" do
    sign_out

    get projects_path
    assert_redirected_to new_session_path
  end

  test "index and show render the inspector" do
    get projects_path

    assert_select "aside.app-inspector"
    assert_select "a.select[data-turbo-frame=inspector]", text: "Plan vacation"
    assert_select "a.select[data-turbo-frame=inspector]", text: "Work"
    assert_select "a.open", text: "Open"

    get project_path(projects(:website))
    assert_select "aside.app-inspector"
    assert_select "turbo-frame#inspector[src*='#{projects(:website).id}']"
  end

  test "show in inspector frame renders project fields" do
    project = projects(:website)

    get project_path(project), headers: { "Turbo-Frame" => "inspector" }

    assert_response :success
    assert_select "turbo-frame#inspector"
    assert_select ".project-inspector"
    assert_select "input[name='project[title]'][value=?]", project.title
    assert_select "select[name='project[project_folder_id]']"
    assert_select "select[name='project[state]']"
  end

  test "update writes project fields" do
    project = projects(:unfiled_project)
    folder = project_folders(:work)

    patch project_path(project), params: {
      project: { title: "Trip", notes: "Pack", project_folder_id: folder.id, state: "dropped" }
    }

    project.reload
    assert_equal "Trip", project.title
    assert_equal "Pack", project.notes
    assert_equal folder.id, project.project_folder_id
    assert project.dropped?
    assert_redirected_to project_path(project)
  end

  test "update via turbo stream removes a card that left the list" do
    project = projects(:unfiled_project)

    patch project_path(project),
          params: { project: { state: "done" }, list_context: "projects_index" },
          as: :turbo_stream

    assert project.reload.done?
    assert_match(/turbo-stream[^>]*action="remove"/, response.body)
  end
end
