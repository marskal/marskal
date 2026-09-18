# frozen_string_literal: true

require "test_helper"

class EmptyStateComponentTest < ViewComponent::TestCase
  test "renders content" do
    render_inline(EmptyStateComponent.new) { "Nothing here" }

    assert_selector "p.empty-state", text: "Nothing here"
  end
end
