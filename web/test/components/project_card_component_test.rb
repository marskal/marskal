# frozen_string_literal: true

require "test_helper"

class ProjectCardComponentTest < ViewComponent::TestCase
  test "inspects the project and offers open" do
    project = projects(:website)

    render_inline(ProjectCardComponent.new(project: project))

    assert_selector "article.project-card .title", text: project.title
    assert_selector "a.select[data-turbo-frame=inspector]", text: project.title
    assert_selector "a.open", text: "Open"
    assert_match %r{/projects/#{project.id}}, rendered_content
    assert_selector ".notes", text: /marketing/i
  end

  test "selected card is marked current" do
    project = projects(:website)

    render_inline(ProjectCardComponent.new(project: project, selected: true))

    assert_selector "article.project-card.is-selected[aria-current=true]"
  end
end
