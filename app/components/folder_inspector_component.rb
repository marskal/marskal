# frozen_string_literal: true

class FolderInspectorComponent < ApplicationComponent
  STATE_OPTIONS = [
    [ "Active", "active" ],
    [ "Dropped", "dropped" ]
  ].freeze

  def initialize(folder:, parent_options:, list_context: nil)
    @folder = folder
    @parent_options = parent_options
    @list_context = list_context
  end

  def state_options
    STATE_OPTIONS
  end
end
