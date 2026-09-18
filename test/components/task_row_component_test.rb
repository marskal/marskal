# frozen_string_literal: true

require "test_helper"

class TaskRowComponentTest < ViewComponent::TestCase
  test "shows project link outside a project context" do
    task = tasks(:project_task)

    render_inline(TaskRowComponent.new(task: task, context: :open))

    assert_selector "article.task-row h2.title", text: task.title
    assert_selector ".project a", text: task.project.title
    assert_selector "button", text: "Done"
    assert_selector "button", text: "Drop"
  end

  test "hides project link on a project page" do
    task = tasks(:project_task)

    render_inline(TaskRowComponent.new(task: task, context: :project))

    assert_selector "h2.title", text: task.title
    assert_no_selector ".project"
  end

  test "inbox to-do offers move to open" do
    task = tasks(:inbox_one)

    render_inline(TaskRowComponent.new(task: task, context: :inbox))

    assert_selector "button", text: "Move to open tasks"
  end
end
