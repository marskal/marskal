require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@YELLING.EXAMPLE ")
    assert_equal("downcased@yelling.example", user.email_address)
  end
end
