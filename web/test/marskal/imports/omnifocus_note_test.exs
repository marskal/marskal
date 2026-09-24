defmodule Marskal.Imports.OmnifocusNoteTest do
  use ExUnit.Case, async: true

  alias Marskal.Imports.OmnifocusNote
  alias Marskal.Imports.Xml

  test "emits markdown paragraphs and links, drops font style bags" do
    xml = """
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
    """

    markdown = OmnifocusNote.to_markdown(Xml.parse!(xml))

    assert markdown =~ "You can then also "

    assert markdown =~
             "[customize what details you see in the Inspector](https://www.omnigroup.com/forward/of4-customize-inspector)"

    assert markdown =~ "The fields you've chosen to hide stay hidden."
    assert markdown =~ "\n\n"
    refute markdown =~ "AppleSystemUIFont"
    refute markdown =~ "<a href"
  end

  test "maps bold italic and strikethrough to markdown" do
    xml = """
    <note>
      <text>
        <p>
          <run>
            <style><value key="font-weight">8</value></style>
            <lit>bold</lit>
          </run>
          <run><lit> and </lit></run>
          <run>
            <style><value key="font-italic">true</value></style>
            <lit>italic</lit>
          </run>
          <run><lit> and </lit></run>
          <run>
            <style><value key="strikethrough-style">single</value></style>
            <lit>gone</lit>
          </run>
          <run>
            <style>
              <value key="font-weight">9</value>
              <value key="link">https://example.com</value>
            </style>
            <lit>docs</lit>
          </run>
        </p>
      </text>
    </note>
    """

    markdown = OmnifocusNote.to_markdown(Xml.parse!(xml))

    assert markdown =~ "**bold**"
    assert markdown =~ "*italic*"
    assert markdown =~ "~~gone~~"
    assert markdown =~ "[**docs**](https://example.com)"
  end
end
