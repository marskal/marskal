# frozen_string_literal: true

require "test_helper"

class ApplicationComponentTest < ActiveSupport::TestCase
  test "scope_class dasherizes the component name" do
    assert_equal "task-row", TaskRowComponent.scope_class
    assert_equal "button", ButtonComponent.scope_class
    assert_equal "empty-state", EmptyStateComponent.scope_class
  end

  test "classes appends modifiers" do
    assert_equal "button", ButtonComponent.classes
    assert_equal "button button--primary", ButtonComponent.classes(:primary)
    assert_equal "button button--ghost", ButtonComponent.classes(:ghost)
  end

  test "each widget stylesheet @scopes its root class" do
    sheets = Rails.root.glob("app/assets/stylesheets/components/*.css")
    assert_operator sheets.size, :>=, 5

    sheets.each do |file|
      name = file.basename(".css").to_s
      assert_includes file.read, "@scope (.#{name})", "#{file} should @scope (.#{name})"
    end
  end
end
