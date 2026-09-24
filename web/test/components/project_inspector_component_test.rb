# frozen_string_literal: true

require "test_helper"

class ProjectInspectorComponentTest < ViewComponent::TestCase
  test "renders fields for every editable project attribute" do
    project = projects(:website)

    render_inline(
      ProjectInspectorComponent.new(
        project: project,
        folder_options: [ [ "Work / Client A", project_folders(:client_a).id ] ]
      )
    )

    assert_selector "section.project-inspector.inspector-form[data-inspect-type=project]"
    assert_field "project[title]", with: project.title
    assert_selector "textarea[name='project[notes]']"
    assert_selector "select[name='project[project_folder_id]'] option[selected]", text: "Work / Client A"
    assert_selector "select[name='project[state]'] option[value='to_do'][selected]"
    assert_selector "a.open", text: "Open project"
    assert_selector "input[type=submit][value=Save]"
  end
end
