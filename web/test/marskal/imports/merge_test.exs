defmodule Marskal.Imports.MergeTest do
  use ExUnit.Case, async: true

  alias Marskal.Imports.Merge

  @base %{"title" => "A", "notes" => "n", "inbox" => true, "project_id" => nil}

  test "takes the source's change where the user left the field" do
    assert {%{"title" => "B"}, []} =
             Merge.fields(:task, @base, @base, %{@base | "title" => "B"}) |> only(["title"])
  end

  test "keeps the user's change, and reports it only when the source changed too" do
    current = %{@base | "notes" => "mine"}

    assert {%{}, []} = Merge.fields(:task, @base, current, @base) |> only(["notes"])

    assert {%{}, ["notes"]} =
             Merge.fields(:task, @base, current, %{@base | "notes" => "theirs"})
             |> only(["notes"])

    assert {%{}, []} = Merge.fields(:task, @base, current, current) |> only(["notes"])
  end

  test "a location merges as one group" do
    current = %{@base | "inbox" => false}
    incoming = %{@base | "project_id" => "p"}

    assert {%{}, ["inbox"]} = Merge.fields(:task, @base, current, incoming) |> only(["inbox"])

    assert {%{"inbox" => true, "project_id" => "p"}, []} =
             Merge.fields(:task, @base, @base, incoming) |> only(["inbox", "project_id"])
  end

  test "tags: the source's additions and removals, minus the user's" do
    assert Merge.tags(~w(a b), ~w(a b mine), ~w(a c)) == {["c"], ["b"]}
    # The user removed b; the source still has it.
    assert Merge.tags(~w(a b), ~w(a), ~w(a b)) == {[], []}
  end

  defp only({patch, kept}, fields),
    do: {Map.take(patch, fields), Enum.filter(kept, &(&1 in fields))}
end
