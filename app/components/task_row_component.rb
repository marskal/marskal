# frozen_string_literal: true

class TaskRowComponent < ApplicationComponent
  def initialize(task:, context: :open)
    @task = task
    @context = context
  end

  def show_project?
    @context != :project && @task.project.present?
  end

  def check_url
    @task.to_do? ? complete_task_path(@task) : reopen_task_path(@task)
  end

  def check_label
    @task.to_do? ? "Mark as done" : "Reopen"
  end

  def check_class
    tokens = [ "check" ]
    tokens << "check--done" if @task.done?
    tokens << "check--dropped" if @task.dropped?
    tokens.join(" ")
  end
end
