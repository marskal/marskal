defmodule Marskal.Rank do
  @moduledoc """
  Fractional sibling order (ADR 0014).

  A rank is a string over `0-9A-Za-z`, compared byte by byte, so rank
  columns use `COLLATE "C"`. `between/2` returns a rank strictly between two
  neighbors without renumbering either, and never one ending in `0`, so
  there is always room for another.
  """

  @digits ~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  @base length(@digits)
  @values @digits |> Enum.with_index() |> Map.new()

  @doc "The first rank in an empty list."
  def first, do: between(nil, nil)

  @doc """
  A rank after `before` and before `later`. `nil` stands for the start or
  the end of the list.
  """
  def between(before, later) do
    a = decode(before || "")
    b = later && decode(later)

    if b && a >= b do
      raise ArgumentError, "rank #{inspect(before)} is not before #{inspect(later)}"
    end

    a |> midpoint(b) |> encode()
  end

  # Digit lists; `nil` for b is the upper end, past every rank. A missing
  # digit in `a` counts as 0.
  defp midpoint([x | a], [x | b]), do: [x | midpoint(a, b)]
  defp midpoint([], [0 | b]), do: [0 | midpoint([], b)]

  defp midpoint(a, b) do
    low = List.first(a, 0)
    high = if b in [nil, []], do: @base, else: hd(b)

    cond do
      high - low > 1 -> [div(low + high + 1, 2)]
      match?([_, _ | _], b) -> [high]
      true -> [low | midpoint(Enum.drop(a, 1), nil)]
    end
  end

  defp decode(rank) do
    rank
    |> String.to_charlist()
    |> Enum.map(fn char ->
      Map.get(@values, char) || raise ArgumentError, "invalid rank #{inspect(rank)}"
    end)
  end

  defp encode(values), do: values |> Enum.map(&Enum.at(@digits, &1)) |> List.to_string()
end
