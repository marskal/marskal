require "test_helper"

Capybara.register_driver :headless_firefox do |app|
  options = Selenium::WebDriver::Firefox::Options.new
  firefox = "/Applications/Firefox.app/Contents/MacOS/firefox"
  options.binary = firefox if File.exist?(firefox)
  options.add_argument("-headless")
  Capybara::Selenium::Driver.new(app, browser: :firefox, options: options)
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :headless_firefox, screen_size: [ 1400, 900 ]

  def sign_in_as(user)
    visit new_session_path
    page.current_window.resize_to(1400, 900)
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "H3mm3l1gh3d"
    click_button "Sign in"
    assert_selector "h1", text: "Open tasks", wait: 10
  end
end
