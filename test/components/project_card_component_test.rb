# frozen_string_literal: true

require "test_helper"

class ProjectCardComponentTest < ViewComponent::TestCase
  test "links to the project" do
    project = projects(:website)

    render_inline(ProjectCardComponent.new(project: project))

    assert_selector "a.project-card .title", text: project.title
    assert_match %r{/projects/#{project.id}}, rendered_content
    assert_selector ".notes", text: /marketing/i
  end
end
