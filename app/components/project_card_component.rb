# frozen_string_literal: true

class ProjectCardComponent < ApplicationComponent
  def initialize(project:)
    @project = project
  end
end
