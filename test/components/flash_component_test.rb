# frozen_string_literal: true

require "test_helper"

class FlashComponentTest < ViewComponent::TestCase
  test "renders notice and alert" do
    render_inline(FlashComponent.new(notice: "Saved", alert: "Nope"))

    assert_selector "p.flash.flash--notice[role=status]", text: "Saved"
    assert_selector "p.flash.flash--alert[role=alert]", text: "Nope"
  end

  test "renders nothing when empty" do
    render_inline(FlashComponent.new)

    assert_no_selector ".flash"
  end
end
