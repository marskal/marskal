defmodule Marskal.SyncFixturesTest do
  @moduledoc """
  The shared vectors in `sync/fixtures`. The Rust client library runs the
  same files (ADR 0018), so both sides mint the same ranks and link ids.
  """

  use ExUnit.Case, async: true

  alias Marskal.Rank
  alias Marskal.Tags.Link

  @fixtures Path.expand("../../../sync/fixtures", __DIR__)

  test "rank.json" do
    vectors = read("rank.json")

    for %{"before" => before, "later" => later, "rank" => rank} <- vectors["between"] do
      assert Rank.between(before, later) == rank, "between(#{inspect(before)}, #{inspect(later)})"
    end

    for %{"rank" => rank, "valid" => valid} <- vectors["valid"] do
      assert Rank.valid?(rank) == valid, "valid?(#{inspect(rank)})"
    end

    for %{"count" => count, "ranks" => ranks} <- vectors["spread"] do
      assert Rank.spread(count) == ranks
    end
  end

  test "link_ids.json" do
    for %{"kind" => kind, "owner_id" => owner, "tag_id" => tag, "id" => id} <-
          read("link_ids.json")["links"] do
      assert Link.id(String.to_existing_atom(kind), owner, tag) == id
    end
  end

  defp read(name), do: @fixtures |> Path.join(name) |> File.read!() |> Jason.decode!()
end
