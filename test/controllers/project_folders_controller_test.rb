require "test_helper"

class ProjectFoldersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "show lists projects and subfolders" do
    get project_folder_path(project_folders(:work))

    assert_response :success
    assert_match "Work", response.body
    assert_match "Client A", response.body
  end

  test "show folder with projects" do
    get project_folder_path(project_folders(:client_a))

    assert_response :success
    assert_match "Launch website", response.body
  end

  test "create root folder" do
    assert_difference -> { @user.project_folders.count }, 1 do
      post project_folders_path, params: { project_folder: { name: "Personal" } }
    end

    folder = @user.project_folders.find_by!(name: "Personal")
    assert folder.active?
    assert_nil folder.parent_id
    assert_redirected_to project_folder_path(folder)
  end

  test "create nested folder" do
    parent = project_folders(:work)

    assert_difference -> { @user.project_folders.count }, 1 do
      post project_folders_path, params: { project_folder: { name: "Client B", parent_id: parent.id } }
    end

    folder = @user.project_folders.find_by!(name: "Client B")
    assert_equal parent, folder.parent
    assert_equal [ "Work" ], folder.parent_path
  end

  test "drop folder" do
    folder = project_folders(:client_a)

    patch drop_project_folder_path(folder)

    assert folder.reload.dropped?
    assert_redirected_to projects_path
  end

  test "cannot access another users folder" do
    get project_folder_path(project_folders(:other_user_folder))
    assert_response :not_found
  end
end
