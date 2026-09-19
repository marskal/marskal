# frozen_string_literal: true

require "test_helper"

class FolderInspectorComponentTest < ViewComponent::TestCase
  test "renders fields for every editable folder attribute" do
    folder = project_folders(:client_a)

    render_inline(
      FolderInspectorComponent.new(
        folder: folder,
        parent_options: [ [ "Work", project_folders(:work).id ] ]
      )
    )

    assert_selector "section.folder-inspector.inspector-form[data-inspect-type=folder]"
    assert_field "project_folder[name]", with: folder.name
    assert_selector "select[name='project_folder[parent_id]'] option[selected]", text: "Work"
    assert_selector "select[name='project_folder[state]'] option[value=active][selected]"
    assert_selector "a.open", text: "Open folder"
    assert_selector "input[type=submit][value=Save]"
  end
end
