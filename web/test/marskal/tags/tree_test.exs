defmodule Marskal.Tags.TreeTest do
  use ExUnit.Case, async: true

  alias Marskal.Tags.Tag
  alias Marskal.Tags.Tree

  # Person › Family › Wife, Person › Old (dropped) › Friend, Waiting (on hold)
  setup do
    person = tag("person", "Person", nil)
    family = tag("family", "Family", person)
    wife = tag("wife", "Wife", family)
    old = tag("old", "Old", person, :dropped)
    friend = tag("friend", "Friend", old)
    waiting = tag("waiting", "Waiting", nil, :on_hold)

    %{tree: Tree.new([person, waiting, family, old, wife, friend])}
  end

  test "lists each tag before its children, siblings in rank order", %{tree: tree} do
    assert Enum.map(Tree.all(tree), & &1.id) == ~w(person family wife old friend waiting)
    assert Tree.subtree_ids(tree, "person") == ~w(person family wife old friend)
  end

  test "Dropped covers the subtree; On Hold stays on its tag", %{tree: tree} do
    assert Tree.state(tree, "old") == :dropped
    assert Tree.state(tree, "friend") == :dropped
    refute Tree.visible?(tree, "friend")

    assert Tree.state(tree, "waiting") == :on_hold
    assert Tree.visible?(tree, "waiting")
  end

  test "an on-hold parent does not hold its children" do
    parent = tag("p", "Parent", nil, :on_hold)
    child = tag("c", "Child", parent)
    tree = Tree.new([parent, child])

    assert Tree.state(tree, "c") == :active
    assert Tree.available?(tree, ["c"])
  end

  test "availability", %{tree: tree} do
    assert Tree.available?(tree, [])
    assert Tree.available?(tree, ["wife"])
    refute Tree.available?(tree, ["wife", "waiting"])
    refute Tree.available?(tree, ["friend"])
    refute Tree.available?(tree, ["old", "friend"])
    assert Tree.available?(tree, ["friend", "wife"])
    assert Tree.available?(tree, ["gone"])
  end

  defp tag(id, name, parent, state \\ :active) do
    %Tag{
      id: id,
      name: name,
      state: state,
      parent_id: parent && parent.id,
      parent_path: if(parent, do: Tag.path(parent), else: []),
      rank: id
    }
  end
end
