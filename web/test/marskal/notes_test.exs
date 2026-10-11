defmodule Marskal.NotesTest do
  use ExUnit.Case, async: true

  test "renders CommonMark links and escapes raw html" do
    html =
      Marskal.Notes.html("See [the docs](https://marskal.example). <script>alert(1)</script>")

    assert html =~ ~s(href="https://marskal.example")
    assert html =~ "the docs"
    refute html =~ "<script"
  end

  test "renders strikethrough and autolinks" do
    html = Marskal.Notes.html("Gone ~~later~~ https://marskal.example")

    assert html =~ "<del>later</del>"
    assert html =~ ~s(href="https://marskal.example")
  end
end
