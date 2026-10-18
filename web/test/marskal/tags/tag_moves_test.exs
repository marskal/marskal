defmodule Marskal.Tags.TagMovesTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.Tags
  alias Marskal.Tags.Tree

  setup do
    %{user: AccountsFixtures.user_fixture()}
  end

  defp tag(user, name, parent_id \\ nil) do
    {:ok, tag} = Tags.create_tag(user, %{"name" => name, "parent_id" => parent_id}, command())
    tag
  end

  defp names(user, parent_id \\ nil) do
    user |> Tags.tree() |> Tree.children(parent_id) |> Enum.map(& &1.name)
  end

  test "a drop puts a tag after a sibling, or under another tag", %{user: user} do
    home = tag(user, "Home")
    work = tag(user, "Work")
    errands = tag(user, "Errands")

    {:ok, _} = Tags.place_tag(user, errands.id, nil, home.id, command())
    assert names(user) == ["Home", "Errands", "Work"]

    {:ok, moved} = Tags.place_tag(user, errands.id, work.id, nil, command())
    assert moved.parent_path == ["Work"]
    assert names(user, work.id) == ["Errands"]
  end

  test "a name already used under the new parent refuses the move", %{user: user} do
    home = tag(user, "Home")
    tag(user, "Garden", home.id)
    garden = tag(user, "Garden")

    assert {:error, %Ecto.Changeset{}} =
             Tags.place_tag(user, garden.id, home.id, :last, command())
  end

  test "indent, outdent, up, and down go by the shown tags", %{user: user} do
    home = tag(user, "Home")
    old = tag(user, "Old")
    work = tag(user, "Work")
    {:ok, _} = Tags.set_tag_state(user, old.id, :dropped, command())

    {:ok, _} = Tags.indent_tag(user, work.id, command())
    assert names(user, home.id) == ["Work"]

    {:ok, _} = Tags.outdent_tag(user, work.id, command())
    assert names(user) == ["Home", "Work", "Old"]

    {:ok, _} = Tags.move_tag_up(user, work.id, command())
    assert names(user) == ["Work", "Home", "Old"]

    assert {:error, :first} = Tags.move_tag_up(user, work.id, command())
    assert {:error, :last} = Tags.move_tag_down(user, home.id, command())
    assert {:error, :top_level} = Tags.outdent_tag(user, home.id, command())
    assert {:error, :first} = Tags.indent_tag(user, work.id, command())
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
