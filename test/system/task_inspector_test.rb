require "application_system_test_case"

class TaskInspectorTest < ApplicationSystemTestCase
  setup do
    sign_in_as(users(:one))
    page.current_window.resize_to(1400, 900)
  end

  test "clicking a task opens the inspector and saves edits" do
    visit root_path

    assert_selector ".app-inspector__empty", text: /Select a task/

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
    assert_selector "aside.app-inspector", text: "Select a task to edit its details."
  end
end
