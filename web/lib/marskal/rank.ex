defmodule Marskal.Rank do
  @moduledoc """
  Fractional sibling order (ADR 0014).

  A rank is a string over `0-9A-Za-z`, compared byte by byte, so rank
  columns use `COLLATE "C"`. `between/2` returns a rank strictly between two
  neighbors without renumbering either, and never one ending in `0`, so
  there is always room for another.

  ## Reading a rank

  Think of a rank as the digits after a decimal point, in base 62: `"V"` is
  about 0.5 of the way through the list, `"l"` about 0.75, `"VV"` a little
  past `"V"`. Putting a sibling between two others takes a value halfway
  between them. When two ranks are adjacent, like `"V"` and `"W"`, there is
  no digit in between, so the rank grows a digit, just as 0.55 fits between
  0.5 and 0.6.

  Three siblings added in turn, then one moved between the first two:

      iex> a = Marskal.Rank.first()
      "V"
      iex> b = Marskal.Rank.between(a, nil)
      "l"
      iex> c = Marskal.Rank.between(b, nil)
      "t"
      iex> Marskal.Rank.between(a, b)
      "d"
      iex> Enum.sort([c, a, b])
      ["V", "l", "t"]

  Only the moved row gets a new rank; its neighbors keep theirs, so a move
  is one field patch.

  ## Why not a float

  Each insert into the same gap halves it. A double has 52 bits of
  precision, so about 50 inserts at one spot, such as moving tasks to the
  top again and again, make the midpoint equal a neighbor. Then the whole
  sibling list needs new ranks. Every renumbered row is a patch that syncs
  to every device, and two offline devices renumbering the same list
  conflict on rows neither user moved (ADR 0014). A string can always grow
  one more digit, so every move stays one patch.

  Clients must place a rank offline and agree with the server. String
  comparison is the same everywhere; floats can round differently on the
  way through JSON and each client's storage. Postgres `numeric` has the
  precision, but client decimal types stop at about 38 digits.

  The cost is length. Each digit adds about 6 bits of room: 1,000 inserts
  into one gap make a rank of roughly 170 characters. Ordinary reordering
  stays at one to three.
  """

  @digits ~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  @base length(@digits)
  @values @digits |> Enum.with_index() |> Map.new()

  @doc "The first rank in an empty list."
  def first, do: between(nil, nil)

  @doc """
  A rank after `before` and before `later`. `nil` stands for the start or
  the end of the list.

  With room between the neighbors, the rank is the digit halfway:

      iex> Marskal.Rank.between("V", "l")
      "d"
      iex> Marskal.Rank.between(nil, "V")
      "G"

  Adjacent neighbors get a longer rank. It starts with the lower one and
  adds a digit halfway to the end:

      iex> Marskal.Rank.between("V", "W")
      "VV"
      iex> Marskal.Rank.between("VV", "W")
      "Vl"

  If the later rank is longer, its first digit alone is enough, since
  `"W"` sorts before `"W1"`:

      iex> Marskal.Rank.between("V", "W1")
      "W"

  At the very front, a rank below `"1"` has to start with `"0"`. That is
  why no rank ends in `0`: there is always something below it.

      iex> Marskal.Rank.between(nil, "1")
      "0V"
      iex> Marskal.Rank.between(nil, "01")
      "00V"
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
  #
  # A shared leading digit is kept ("VA", "VC" -> "V" + midpoint("A", "C")).
  defp midpoint([x | a], [x | b]), do: [x | midpoint(a, b)]
  defp midpoint([], [0 | b]), do: [0 | midpoint([], b)]

  defp midpoint(a, b) do
    low = List.first(a, 0)
    high = if b in [nil, []], do: @base, else: hd(b)

    cond do
      # Room for a digit between: "V", "l" -> "d".
      high - low > 1 -> [div(low + high + 1, 2)]
      # b's first digit alone is below b: "V", "W1" -> "W".
      match?([_, _ | _], b) -> [high]
      # Adjacent: keep a's digit and go halfway from the rest of a to the
      # end: "V", "W" -> "V" + "V".
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
