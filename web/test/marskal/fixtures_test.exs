defmodule Marskal.FixturesTest do
  @moduledoc """
  The shared vectors in `core/fixtures`. The Rust `rules` and `replica`
  crates run the same files (ADR 0039), so both sides mint the same ranks
  and link ids, read dates alike, and match a typed path the same way.
  """

  use ExUnit.Case, async: true

  alias Marskal.PathSearch
  alias Marskal.Rank
  alias Marskal.Tags.Link
  alias Marskal.Tags.Search
  alias Marskal.Tags.Tag
  alias Marskal.Tags.Tree

  @fixtures Path.expand("../../../core/fixtures", __DIR__)

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

  test "dates.json" do
    fields = %{"defer" => :defer_until, "planned" => :planned_at, "due" => :due_at}

    for v <- read("dates.json")["from_local"] do
      time = v["time"] && Time.from_iso8601!(v["time"])
      {:ok, at, 0} = DateTime.from_iso8601(v["at"])

      assert Marskal.Dates.from_local(
               Date.from_iso8601!(v["date"]),
               time,
               fields[v["field"]],
               v["zone"]
             ) ==
               at,
             "#{v["zone"]} #{v["date"]} #{v["time"]}: #{v["why"]}"
    end
  end

  test "date_input.json" do
    for v <- read("date_input.json")["parse"] do
      result =
        Marskal.DateInput.parse(v["text"], NaiveDateTime.from_iso8601!(v["now"]),
          week_start: v["week_start"],
          order: String.to_existing_atom(v["order"]),
          day_month: String.to_existing_atom(v["day_month"]),
          evening: Time.from_iso8601!(v["evening"]),
          language: v["language"]
        )

      expected =
        case v["result"] do
          "ok" -> {:ok, Date.from_iso8601!(v["date"]), v["time"] && Time.from_iso8601!(v["time"])}
          "blank" -> :blank
          "error" -> :error
        end

      assert result == expected, "#{inspect(v["text"])} at #{v["now"]}: #{v["why"]}"
    end
  end

  test "path_search.json" do
    vectors = read("path_search.json")

    for v <- vectors["match"] do
      pieces = PathSearch.pieces(v["query"])
      skipped = if pieces == [], do: nil, else: PathSearch.match(v["path"], pieces)

      assert skipped == v["skipped"],
             "#{inspect(v["query"])} on #{inspect(v["path"])}: #{v["why"]}"
    end

    for v <- vectors["exact"] do
      assert PathSearch.exact?(v["name"], PathSearch.whole(v["query"])) == v["exact"],
             "#{inspect(v["name"])} and #{inspect(v["query"])}"
    end

    tree = vectors["tags"]["rows"] |> tags() |> Tree.new()

    for v <- vectors["tags"]["search"] do
      paths = tree |> Search.run(v["query"], vectors["tags"]["limit"]) |> Enum.map(&Tag.path/1)
      assert paths == v["paths"], inspect(v["query"])
    end
  end

  # Tag structs from the rows, in the order Tags.list_tags/1 gives them.
  defp tags(rows) do
    by_id = Map.new(rows, &{&1["id"], &1})

    ancestors = fn
      %{"parent_id" => nil}, _ -> []
      %{"parent_id" => parent}, f -> f.(by_id[parent], f) ++ [by_id[parent]["name"]]
    end

    rows
    |> Enum.map(fn row ->
      %Tag{
        id: row["id"],
        name: row["name"],
        state: String.to_existing_atom(row["state"]),
        parent_id: row["parent_id"],
        parent_path: ancestors.(row, ancestors),
        rank: row["rank"]
      }
    end)
    |> Enum.sort_by(&{is_nil(&1.rank), &1.rank, &1.id})
  end

  defp read(name), do: @fixtures |> Path.join(name) |> File.read!() |> Jason.decode!()
end
