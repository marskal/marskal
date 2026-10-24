defmodule Marskal.PathSearch do
  @moduledoc """
  Matches a typed query against a path of names, such as a tag's path or a
  project's folders and title (ADR 0005, ADR 0033).

  The query is split on `/ : › > \\`, and so is every segment of the path,
  so one rule covers both readings of `som/may`: the literal name
  `Someday/maybe` and the path `Someday › Maybach`. Each piece must be a
  case-insensitive prefix of a part, or of a word in it, in order. The last
  piece must land in the last segment, the record's own name, so a query
  finds the record, not everything under the ancestor it names. Pieces may
  skip ancestors: `per/wi` finds `Person › Family › Wife`.
  """

  @separators ["/", ":", "›", ">", "\\"]

  def separators, do: @separators

  @doc "The query's pieces, normalized; `[]` for a blank query."
  def pieces(query), do: split(query)

  @doc "The whole query, normalized, to compare with a name for an exact match."
  def whole(query), do: query |> normalize() |> String.trim()

  @doc "Whether a name equals the query, ignoring case."
  def exact?(name, whole), do: normalize(name) == whole

  @doc """
  The number of path segments skipped between the first match and the
  last segment, or nil when the path does not match.
  """
  def match(path, pieces) when is_list(path) and pieces != [] do
    segments = Enum.map(path, &split/1)
    own = length(segments) - 1

    parts =
      for {segment, index} <- Enum.with_index(segments), part <- segment, do: {part, index}

    case place(pieces, parts) do
      {first, ^own} -> own - first + 1 - min(length(pieces), own - first + 1)
      _ -> nil
    end
  end

  # Matches pieces to parts in order, greedily from the right, which finds a
  # match whenever one exists and puts the last piece as late as possible.
  # Returns {segment of the first piece, segment of the last piece}.
  defp place(pieces, parts) do
    pieces
    |> Enum.reverse()
    |> Enum.reduce_while({Enum.reverse(parts), nil, nil}, fn piece, {remaining, _first, last} ->
      case Enum.drop_while(remaining, &later_piece?(&1, piece)) do
        [] -> {:halt, :nomatch}
        [{_, index} | rest] -> {:cont, {rest, index, last || index}}
      end
    end)
    |> case do
      {_, first, last} -> {first, last}
      :nomatch -> nil
    end
  end

  defp later_piece?({part, _index}, piece), do: not prefix?(part, piece)

  defp prefix?(part, piece) do
    String.starts_with?(part, piece) or
      part |> String.split() |> Enum.any?(&String.starts_with?(&1, piece))
  end

  defp split(text) do
    text
    |> normalize()
    |> String.split(@separators)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize(text), do: text |> String.normalize(:nfc) |> String.downcase()
end
