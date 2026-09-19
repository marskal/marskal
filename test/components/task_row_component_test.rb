# frozen_string_literal: true

require "test_helper"

class TaskRowComponentTest < ViewComponent::TestCase
  test "shows project link outside a project context" do
    task = tasks(:project_task)

    render_inline(TaskRowComponent.new(task: task, context: :open))

    assert_selector "article.task-row h2.title", text: task.title
    assert_selector "a.select[data-turbo-frame=inspector]", text: task.title
    assert_selector ".project a", text: task.project.title
    assert_selector "form.check-form button.check[aria-label='Mark as done']"
    assert_selector "button.check .check__idle"
    assert_selector "button.check .check__hint"
    assert_selector "button", text: "Drop"
    assert_no_selector "button", text: "Done"
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

  test "done task shows a completed check that reopens" do
    task = tasks(:done_one)

    render_inline(TaskRowComponent.new(task: task, context: :open))

    assert_selector "form.check-form button.check.check--done[aria-label='Reopen']"
    assert_selector "button.check .check__complete"
    assert_no_selector "button.check .check__idle"
    assert_no_selector "button.check .check__hint"
  end

  test "dropped task shows square-off" do
    task = tasks(:dropped_one)

    render_inline(TaskRowComponent.new(task: task, context: :open))

    assert_selector "form.check-form button.check.check--dropped[aria-label='Reopen']"
    assert_selector "button.check .check__dropped"
    assert_no_selector "button.check .check__idle"
  end

  test "selected row is marked current" do
    task = tasks(:open_one)

    render_inline(TaskRowComponent.new(task: task, context: :open, selected: true))

    assert_selector "article.task-row.is-selected[aria-current=true]"
  end
end
