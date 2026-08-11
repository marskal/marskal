require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "index lists open projects only for current user" do
    get projects_path

    assert_response :success
    assert_select "h1", "Projects"
    assert_match "Launch website", response.body
    assert_no_match "Finish onboarding", response.body
    assert_no_match "Secret project", response.body
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

    project = @user.projects.order(:id).last
    assert_equal "Tax return", project.title
    assert project.to_do?
    assert_redirected_to project_path(project)
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
end
