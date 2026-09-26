defmodule Marskal.NotesTest do
  use ExUnit.Case, async: true

  test "renders CommonMark links and escapes raw html" do
    html = Marskal.Notes.html("See [the docs](https://example.com). <script>alert(1)</script>")

    assert html =~ ~s(href="https://example.com")
    assert html =~ "the docs"
    refute html =~ "<script"
  end

  test "renders strikethrough and autolinks" do
    html = Marskal.Notes.html("Gone ~~later~~ https://example.com")

    assert html =~ "<del>later</del>"
    assert html =~ ~s(href="https://example.com")
  end
end
