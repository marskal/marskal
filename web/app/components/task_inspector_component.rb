# frozen_string_literal: true

class TaskInspectorComponent < ApplicationComponent
  STATE_OPTIONS = [
    [ "To-Do", "to_do" ],
    [ "Done", "done" ],
    [ "Dropped", "dropped" ]
  ].freeze

  def initialize(task:, projects:, list_context: "open", list_project_id: nil)
    @task = task
    @projects = projects
    @list_context = list_context
    @list_project_id = list_project_id
  end

  def project_options
    @projects.map { |project| [ project.title, project.id ] }
  end

  def state_options
    STATE_OPTIONS
  end
end
