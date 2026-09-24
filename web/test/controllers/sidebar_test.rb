require "test_helper"

class SidebarTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "header brand shows the app icon and name" do
    get root_path

    assert_response :success
    assert_select ".app-header__brand a[href=?]", root_path do
      assert_select "img.app-header__logo[src='/icon.svg']"
      assert_select "span", text: "Marskal"
    end
    assert_select "link[rel=icon][href='/icon.svg']"
    assert_select "link[rel=apple-touch-icon][href='/icon.png']"
  end

  test "authenticated pages show the project folder tree" do
    get root_path

    assert_response :success
    assert_select "aside.app-sidebar"
    assert_select ".app-sidebar a", text: "Open"
    assert_select ".app-sidebar a", text: "Inbox"
    assert_select ".app-sidebar a", text: "Projects"
    assert_select ".app-sidebar a", text: "Import"
    assert_select ".app-sidebar a", text: "Developer"
    assert_select ".app-sidebar", text: /Work/
    assert_select ".app-sidebar", text: /Client A/
    assert_select ".app-sidebar", text: /Launch website/
    assert_select ".app-sidebar", text: /Plan vacation/
    assert_select ".app-sidebar", text: /Finish onboarding/, count: 0
    assert_select ".app-sidebar", text: /Old stuff/, count: 0
    assert_select ".app-sidebar", text: /Secret project/, count: 0
    assert_select ".app-sidebar", text: /Their Work/, count: 0
    assert_select ".app-sidebar [data-sidebar-folder-id=?]", project_folders(:work).id do
      assert_select "a", text: "Client A"
      assert_select "a", text: "Launch website"
    end
    assert_select ".app-sidebar svg", minimum: 4
  end

  test "highlights the current project" do
    get project_path(projects(:website))

    assert_select ".app-sidebar a[aria-current=page]", text: "Launch website"
  end

  test "highlights the current folder" do
    get project_folder_path(project_folders(:work))

    assert_select ".app-sidebar a[aria-current=page]", text: "Work"
  end

  test "highlights open stream" do
    get root_path

    assert_select ".app-sidebar a[aria-current=page]", text: "Open"
  end

  test "does not show sidebar when signed out" do
    sign_out

    get new_session_path

    assert_select "aside.app-sidebar", count: 0
  end
end
