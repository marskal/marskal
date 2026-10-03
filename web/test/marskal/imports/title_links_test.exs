defmodule Marskal.Imports.TitleLinksTest do
  use ExUnit.Case, async: true

  alias Marskal.Imports.TitleLinks

  test "a title that is one link becomes its text and URL" do
    assert TitleLinks.split("[Fællesarrangementer 2026](https://www.vivit.dk/kalender/)") ==
             {"Fællesarrangementer 2026", "https://www.vivit.dk/kalender/", []}
  end

  test "a link inside a sentence keeps the words around it" do
    assert TitleLinks.split("Solve [PROJ-12](https://jira.example/browse/PROJ-12) today") ==
             {"Solve PROJ-12 today", "https://jira.example/browse/PROJ-12", []}
  end

  test "the first link is the URL; the others go to the notes" do
    {title, url, more} = TitleLinks.split("Compare [a](https://a.example) and [b](file:///tmp/b)")

    assert title == "Compare a and b"
    assert url == "https://a.example"
    assert more == ["[b](file:///tmp/b)"]
    assert TitleLinks.notes("Old notes", more) == "Old notes\n\n- [b](file:///tmp/b)"
    assert TitleLinks.notes(nil, more) == "- [b](file:///tmp/b)"
    assert TitleLinks.notes("Old notes", []) == "Old notes"
  end

  test "an address with parentheses, and a link with no text" do
    assert TitleLinks.split("[Rust](https://en.wikipedia.org/wiki/Rust_(language))") ==
             {"Rust", "https://en.wikipedia.org/wiki/Rust_(language)", []}

    assert TitleLinks.split("Read [](https://a.example/x)") ==
             {"Read https://a.example/x", "https://a.example/x", []}
  end

  test "a bare web address becomes the URL and stays in the title" do
    assert TitleLinks.split("Read https://a.example/post.") ==
             {"Read https://a.example/post.", "https://a.example/post", []}

    assert TitleLinks.split("(see https://a.example/x)") ==
             {"(see https://a.example/x)", "https://a.example/x", []}
  end

  test "a script link stays as written and is no URL" do
    assert TitleLinks.split("[click](javascript:alert(1))") ==
             {"[click](javascript:alert(1))", nil, []}

    assert TitleLinks.split("Buy milk") == {"Buy milk", nil, []}
  end
end
