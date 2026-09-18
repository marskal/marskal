# frozen_string_literal: true

class TaskRowComponent < ApplicationComponent
  def initialize(task:, context: :open)
    @task = task
    @context = context
  end

  def show_project?
    @context != :project && @task.project.present?
  end
end
