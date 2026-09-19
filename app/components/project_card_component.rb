# frozen_string_literal: true

class ProjectCardComponent < ApplicationComponent
  def initialize(project:, selected: false, list_context: nil, list_folder_id: nil)
    @project = project
    @selected = selected
    @list_context = list_context
    @list_folder_id = list_folder_id
  end

  def inspect_url
    extra = {}
    extra[:list_context] = @list_context if @list_context.present?
    extra[:list_folder_id] = @list_folder_id if @list_folder_id.present?
    project_path(@project, extra)
  end
end
