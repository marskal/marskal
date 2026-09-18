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
end
