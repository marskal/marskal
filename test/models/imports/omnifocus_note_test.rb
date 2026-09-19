# frozen_string_literal: true

require "test_helper"

class Imports::OmnifocusNoteTest < ActiveSupport::TestCase
  test "emits markdown paragraphs and links, drops font style bags" do
    xml = <<~XML
      <note>
        <text>
          <p>
            <run><lit>You can then also </lit></run>
            <run>
              <style>
                <value key="font-family">.AppleSystemUIFont</value>
                <value key="link">https://www.omnigroup.com/forward/of4-customize-inspector</value>
              </style>
              <lit>customize what details you see in the Inspector</lit>
            </run>
            <run><lit>, choosing what to show by default.</lit></run>
          </p>
          <p/>
          <p>
            <run><lit>The fields you've chosen to hide stay hidden.</lit></run>
          </p>
        </text>
      </note>
    XML
    node = Nokogiri::XML(xml).root
    markdown = Imports::OmnifocusNote.to_markdown(node)

    assert_includes markdown, "You can then also "
    assert_includes markdown, "[customize what details you see in the Inspector](https://www.omnigroup.com/forward/of4-customize-inspector)"
    assert_includes markdown, "The fields you've chosen to hide stay hidden."
    assert_includes markdown, "\n\n"
    assert_not_includes markdown, "AppleSystemUIFont"
    assert_not_includes markdown, "<a href"
  end
end
