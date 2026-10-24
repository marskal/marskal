defmodule Marskal.Tags.Search do
  @moduledoc """
  Tag autocomplete (ADR 0005), matching a tag's path as
  `Marskal.PathSearch` describes.

  Dropped tags, and tags under them, are not offered.
  """

  alias Marskal.PathSearch
  alias Marskal.Tags.Tag
  alias Marskal.Tags.Tree

  @limit 20

  def separators, do: PathSearch.separators()

  @doc "Matching tags, best first."
  def run(%Tree{} = tree, query, limit \\ @limit) do
    pieces = PathSearch.pieces(query)
    whole = PathSearch.whole(query)

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
    case PathSearch.match(Tag.path(tag), pieces) do
      nil -> []
      skipped -> [{rank(tag, whole, skipped, tree), tag}]
    end
  end

  # Exact name first, then fewer skipped segments, then shallower, then
  # tree order.
  defp rank(tag, whole, skipped, tree) do
    exact = if PathSearch.exact?(tag.name, whole), do: 0, else: 1
    {exact, skipped, length(tag.parent_path), Tree.position(tree, tag.id)}
  end
end
