require "application_system_test_case"

class TaskInspectorTest < ApplicationSystemTestCase
  setup do
    sign_in_as(users(:one))
    page.current_window.resize_to(1400, 900)
  end

  test "clicking a task opens the inspector and saves edits" do
    visit root_path

    assert_selector ".app-inspector__empty", text: /Select a task, project, or folder/

    click_link "Write Phase 1 tests"

    assert_selector ".task-inspector"
    assert_selector ".task-row.is-selected", text: "Write Phase 1 tests"
    within ".task-inspector" do
      assert_field "Title", with: "Write Phase 1 tests"
      assert_selector "select[name='task[project_id]']"
      assert_field "Inbox"
      assert_selector "select[name='task[state]']"
    end

    within ".task-inspector" do
      fill_in "Notes", with: "Edited from the pane"
      fill_in "Title", with: "Renamed in inspector"
      click_button "Save"
    end

    assert_selector ".task-row.is-selected", text: "Renamed in inspector"
    within ".task-inspector" do
      assert_field "Title", with: "Renamed in inspector"
    end
    assert_equal "Edited from the pane", tasks(:open_one).reload.notes
  end

  test "narrow screens use a slide-over inspector" do
    page.current_window.resize_to(390, 844)
    visit root_path

    assert_no_selector ".app.is-inspector-open"
    click_link "Write Phase 1 tests"

    assert_selector ".app.is-inspector-open"
    assert_selector ".task-inspector"
    within ".task-inspector" do
      assert_field "Title", with: "Write Phase 1 tests"
    end

    find("button.app-inspector__close").click

    assert_no_selector ".app.is-inspector-open"
    assert_no_selector ".task-row.is-selected"
    assert_selector "aside.app-inspector", text: /Select a task, project, or folder/
  end

  test "clicking a project opens the inspector and saves edits" do
    visit projects_path

    within ".project-list" do
      click_link "Plan vacation"
    end

    assert_selector ".project-inspector"
    within ".project-inspector" do
      assert_field "Title", with: "Plan vacation"
      fill_in "Title", with: "Summer trip"
      click_button "Save"
    end

    assert_selector ".project-card.is-selected", text: "Summer trip"
    assert_equal "Summer trip", projects(:unfiled_project).reload.title
  end

  test "opening a project auto-loads it in the inspector" do
    visit project_path(projects(:website))

    assert_selector ".project-inspector"
    within ".project-inspector" do
      assert_field "Title", with: "Launch website"
      assert_selector "select[name='project[project_folder_id]']"
    end
  end

  test "clicking a folder opens the inspector" do
    visit projects_path

    click_link "Work", href: /list_context=projects_index/

    assert_selector ".folder-inspector"
    within ".folder-inspector" do
      assert_field "Name", with: "Work"
    end
  end
end
