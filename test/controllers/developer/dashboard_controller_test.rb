# frozen_string_literal: true

require "test_helper"

class Developer::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "show is available when signed in" do
    get developer_root_path

    assert_response :success
    assert_select "h1", text: "Developer"
    assert_select "form[action=?]", developer_reset_work_path
  end

  test "reset_work wipes this user only" do
    assert users(:one).tasks.exists?
    assert users(:two).tasks.exists?

    post developer_reset_work_path

    assert_redirected_to developer_root_path
    assert_not users(:one).tasks.exists?
    assert_not users(:one).projects.exists?
    assert_not users(:one).project_folders.exists?
    assert_not users(:one).import_batches.exists?
    assert users(:two).tasks.exists?
    assert users(:two).projects.exists?
  end
end
