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

  test "show renders the inspector" do
    folder = project_folders(:work)

    get project_folder_path(folder)

    assert_select "aside.app-inspector"
    assert_select "turbo-frame#inspector[src*='#{folder.id}']"
    assert_select "a.select[data-turbo-frame=inspector]", text: "Client A"
  end

  test "show in inspector frame renders folder fields" do
    folder = project_folders(:client_a)

    get project_folder_path(folder), headers: { "Turbo-Frame" => "inspector" }

    assert_response :success
    assert_select "turbo-frame#inspector"
    assert_select ".folder-inspector"
    assert_select "input[name='project_folder[name]'][value=?]", folder.name
    assert_select "select[name='project_folder[parent_id]']"
    assert_select "select[name='project_folder[state]']"
    assert_select "select[name='project_folder[parent_id]'] option[value=?]", folder.id, count: 0
  end

  test "update writes folder fields" do
    folder = project_folders(:client_a)

    patch project_folder_path(folder), params: {
      project_folder: { name: "Client Alpha", parent_id: "", state: "dropped" }
    }

    folder.reload
    assert_equal "Client Alpha", folder.name
    assert_nil folder.parent_id
    assert folder.dropped?
    assert_redirected_to project_folder_path(folder)
  end

  test "update via turbo stream removes a dropped folder from the index tree" do
    folder = project_folders(:client_a)

    patch project_folder_path(folder),
          params: { project_folder: { state: "dropped" }, list_context: "projects_index" },
          as: :turbo_stream

    assert folder.reload.dropped?
    assert_match(/turbo-stream[^>]*action="remove"/, response.body)
  end
end
