defmodule MarskalWeb.TaskListTest do
  use ExUnit.Case, async: true

  alias MarskalWeb.TaskList

  defp rows(ids), do: Enum.map(ids, &%{id: &1})
  defp ids(rows), do: Enum.map(rows, & &1.id)

  test "a row that left goes back after the row it followed" do
    shown = rows(~w(a b c d))
    lingering = Map.new(rows(~w(b c)), &{&1.id, &1})

    assert ids(TaskList.merge(shown, rows(~w(a d)), lingering)) == ~w(a b c d)
  end

  test "a row that led the list stays first, and new rows keep their places" do
    shown = rows(~w(a b))
    lingering = %{"a" => %{id: "a"}}

    assert ids(TaskList.merge(shown, rows(~w(new b)), lingering)) == ~w(a new b)
  end

  test "a row that moved elsewhere is not an anchor" do
    shown = rows(~w(a moved b))
    lingering = %{"b" => %{id: "b"}}

    assert ids(TaskList.merge(shown, rows(~w(a)), lingering)) == ~w(a b)
  end

  test "nothing lingering leaves the fresh list alone" do
    assert ids(TaskList.merge(rows(~w(a)), rows(~w(b)), %{})) == ~w(b)
  end
end
