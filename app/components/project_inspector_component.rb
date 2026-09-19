# frozen_string_literal: true

class ProjectInspectorComponent < ApplicationComponent
  STATE_OPTIONS = [
    [ "To-Do", "to_do" ],
    [ "Done", "done" ],
    [ "Dropped", "dropped" ]
  ].freeze

  def initialize(project:, folder_options:, list_context: nil, list_folder_id: nil)
    @project = project
    @folder_options = folder_options
    @list_context = list_context
    @list_folder_id = list_folder_id
  end

  def state_options
    STATE_OPTIONS
  end
end
