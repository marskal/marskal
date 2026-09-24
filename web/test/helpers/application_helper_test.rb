require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  include RailsIcons::Helpers::IconHelper

  test "icon helper renders Lucide svg" do
    html = icon("folder")

    assert_match(/<svg/, html)
    assert_match(/class="[^"]*\bicon\b/, html)
  end

  test "btn helper maps to ButtonComponent classes" do
    assert_equal "button", btn
    assert_equal "button button--primary", btn(:primary)
  end

  test "formatted_notes renders CommonMark links" do
    html = formatted_notes("See [the docs](https://example.com).")

    assert_includes html, 'href="https://example.com"'
    assert_includes html, "the docs"
    assert_not_includes html, "<script"
  end

  test "inspect_link_data targets the inspector frame" do
    task = tasks(:open_one)
    data = inspect_link_data(task)

    assert_equal "inspector", data[:turbo_frame]
    assert_equal task.id, data[:inspector_id_param]
    assert_equal "task", data[:inspector_type_param]
    assert_equal "project", inspect_type_for(projects(:website))
    assert_equal "folder", inspect_type_for(project_folders(:work))
  end

  test "formatted_notes renders GFM strikethrough and autolinks" do
    html = formatted_notes("Gone ~~later~~ https://example.com")

    assert_includes html, "<del>later</del>"
    assert_includes html, 'href="https://example.com"'
  end
end
