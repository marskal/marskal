defmodule Marskal.Tags.SearchTest do
  use ExUnit.Case, async: true

  alias Marskal.Tags.Search
  alias Marskal.Tags.Tag
  alias Marskal.Tags.Tree

  # Tree.new takes tags in sibling order, as Tags.list_tags/1 returns them.
  setup do
    someday = tag("Someday", nil)
    maybach = tag("Maybach", someday)
    lists = tag("Lists", nil)
    maybe = tag("Someday/maybe", lists)
    person = tag("Person", nil)
    family = tag("Family", person)
    wife = tag("Wife", family)
    old = tag("Old wife", person)
    gone = tag("Gone", nil, :dropped)
    gone_child = tag("Wifi", gone)
    coffee = tag("Re: ☕", nil)

    tags = [someday, maybach, lists, maybe, person, family, wife, old, gone, gone_child, coffee]
    %{tree: Tree.new(tags)}
  end

  test "som/may finds the literal name and the path", %{tree: tree} do
    assert names(tree, "som/may") == ["Someday › Maybach", "Lists › Someday/maybe"]
  end

  test "every common separator reads as a path", %{tree: tree} do
    for query <- ["som:may", "som › may", "som>may", "som\\may", "som / may"] do
      assert "Someday › Maybach" in names(tree, query), query
    end
  end

  test "pieces may skip ancestors, fewer skips first", %{tree: tree} do
    assert names(tree, "per/wi") == ["Person › Old wife", "Person › Family › Wife"]
  end

  test "the last piece must land in the tag's own name", %{tree: tree} do
    refute "Person › Family" in names(tree, "per/fam/wife")
    assert names(tree, "person") == ["Person"]
  end

  test "exact names rank first, then shallower tags", %{tree: tree} do
    assert names(tree, "wife") == ["Person › Family › Wife", "Person › Old wife"]
    assert names(tree, "some") |> hd() == "Someday"
  end

  test "matches ignore case and match words inside a name", %{tree: tree} do
    assert names(tree, "MAYBACH") == ["Someday › Maybach"]
    assert "Person › Old wife" in names(tree, "wi")
  end

  test "dropped tags and their children are not offered", %{tree: tree} do
    assert names(tree, "gone") == []
    refute "Gone › Wifi" in names(tree, "wi")
  end

  test "emoji and a blank query", %{tree: tree} do
    assert names(tree, "re: ☕") == ["Re: ☕"]
    assert names(tree, " / ") == []
  end

  defp names(tree, query) do
    tree |> Search.run(query) |> Enum.map(&Enum.join(Tag.path(&1), " › "))
  end

  defp tag(name, parent, state \\ :active) do
    %Tag{
      id: Ecto.UUID.generate(),
      name: name,
      state: state,
      parent_id: parent && parent.id,
      parent_path: if(parent, do: Tag.path(parent), else: []),
      rank: "V"
    }
  end
end
