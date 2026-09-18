# frozen_string_literal: true

require "test_helper"

class ButtonComponentTest < ViewComponent::TestCase
  test "renders a button with the primary modifier" do
    render_inline(ButtonComponent.new(variant: :primary)) { "Save" }

    assert_selector "button.button.button--primary[type=button]", text: "Save"
  end

  test "renders a link when href is set" do
    render_inline(ButtonComponent.new(href: "/inbox", variant: :ghost)) { "Inbox" }

    assert_selector "a.button.button--ghost[href='/inbox']", text: "Inbox"
  end
end
