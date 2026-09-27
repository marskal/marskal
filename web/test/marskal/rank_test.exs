defmodule Marskal.RankTest do
  use ExUnit.Case, async: true

  alias Marskal.Rank

  doctest Marskal.Rank

  test "the first rank leaves room on both sides" do
    first = Rank.first()
    assert Rank.between(nil, first) < first
    assert Rank.between(first, nil) > first
  end

  test "a rank always fits between two neighbors" do
    ranks =
      Enum.reduce(1..300, [Rank.first()], fn i, ranks ->
        # Crowd the front, the back, and one gap in the middle.
        at = Enum.at([0, length(ranks), 1], rem(i, 3))
        before = if at == 0, do: nil, else: Enum.at(ranks, at - 1)
        later = Enum.at(ranks, at)
        List.insert_at(ranks, at, Rank.between(before, later))
      end)

    assert ranks == Enum.sort(ranks)
    assert ranks == Enum.uniq(ranks)
    refute Enum.any?(ranks, &String.ends_with?(&1, "0"))
  end

  test "a rank fits between a key and its own extension" do
    assert Rank.between("V", "V1") > "V"
    assert Rank.between("V", "V1") < "V1"
    assert Rank.between(nil, "01") < "01"
  end

  test "neighbors out of order are refused" do
    assert_raise ArgumentError, fn -> Rank.between("b", "a") end
    assert_raise ArgumentError, fn -> Rank.between("a", "a") end
    assert_raise ArgumentError, fn -> Rank.between("a-", nil) end
  end
end
