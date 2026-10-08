defmodule Marskal.Tags.Search do
  @moduledoc """
  Tag autocomplete (ADR 0005).

  The query is split on `/ : › > \\`, and so is every segment of a tag's
  path, so one rule covers both readings of `som/may`: the literal name
  `Someday/maybe` and the path `Someday › Maybach`. Each piece must be a
  case-insensitive prefix of a part, or of a word in it, in order. The last
  piece must land in the tag's own name, so a query finds the tag, not
  every child of the ancestor it names. Pieces may skip ancestors:
  `per/wi` finds `Person › Family › Wife`.

  Dropped tags, and tags under them, are not offered.
  """

  alias Marskal.Tags.Tag
  alias Marskal.Tags.Tree

  @separators ["/", ":", "›", ">", "\\"]
  @limit 20

  def separators, do: @separators

  @doc "Matching tags, best first."
  def run(%Tree{} = tree, query, limit \\ @limit) do
    pieces = split(query)
    whole = query |> normalize() |> String.trim()

    if pieces == [] do
      []
    else
      tree
      |> Tree.all()
      |> Enum.filter(&Tree.visible?(tree, &1.id))
      |> Enum.flat_map(&ranked(tree, &1, pieces, whole))
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.take(limit)
      |> Enum.map(&elem(&1, 1))
    end
  end

  defp ranked(tree, tag, pieces, whole) do
    case match(tag, pieces) do
      nil -> []
      skipped -> [{rank(tag, whole, skipped, tree), tag}]
    end
  end

  # Exact name first, then fewer skipped segments, then shallower, then
  # tree order.
  defp rank(tag, whole, skipped, tree) do
    exact = if normalize(tag.name) == whole, do: 0, else: 1
    {exact, skipped, length(tag.parent_path), Tree.position(tree, tag.id)}
  end

  # Returns the number of path segments skipped between the first match
  # and the tag, or nil when the tag does not match.
  defp match(%Tag{} = tag, pieces) do
    segments = Enum.map(Tag.path(tag), &split/1)
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
