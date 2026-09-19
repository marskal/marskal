# frozen_string_literal: true

require "test_helper"

class TaskInspectorComponentTest < ViewComponent::TestCase
  test "renders fields for every editable task attribute" do
    task = tasks(:project_task)

    render_inline(
      TaskInspectorComponent.new(
        task: task,
        projects: [ projects(:website), projects(:unfiled_project) ],
        list_context: "open"
      )
    )

    assert_selector "section.task-inspector.inspector-form[data-inspect-type=task][data-inspect-id='#{task.id}']"
    assert_field "task[title]", with: task.title
    assert_selector "textarea[name='task[notes]']"
    assert_select_project_options
    assert_selector "input[name='task[inbox]']"
    assert_selector "select[name='task[state]'] option[value='to_do'][selected]"
    assert_selector "input[type=submit][value=Save]"
    assert_text "Created"
    assert_text "Updated"
  end

  test "shows validation errors" do
    task = tasks(:open_one)
    task.title = ""
    task.validate

    render_inline(TaskInspectorComponent.new(task: task, projects: []))

    assert_selector ".errors", text: /blank/i
  end

  private
    def assert_select_project_options
      assert_selector "select[name='task[project_id]'] option", text: "No project"
      assert_selector "select[name='task[project_id]'] option[selected]", text: "Launch website"
      assert_selector "select[name='task[project_id]'] option", text: "Plan vacation"
    end
end
