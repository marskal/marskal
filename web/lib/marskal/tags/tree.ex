defmodule Marskal.Tags.Tree do
  @moduledoc """
  A user's live tags as a tree, built once per request (ADR 0005).

  Everything here is a pure function of the tags. A tag's effective state
  is Dropped if it or any ancestor is dropped; otherwise it is its own
  state, since On Hold applies to that tag only.
  """

  alias Marskal.Tags.Tag

  defstruct by_id: %{}, children: %{}, order: %{}, states: %{}

  @doc "Builds the tree from tags in sibling order, as `Tags.list_tags/1` returns them."
  def new(tags) do
    by_id = Map.new(tags, &{&1.id, &1})

    children =
      tags
      |> Enum.filter(&(is_nil(&1.parent_id) or Map.has_key?(by_id, &1.parent_id)))
      |> Enum.group_by(& &1.parent_id)

    tree = %__MODULE__{by_id: by_id, children: children}

    walk = depth_first(tree, nil)

    %{
      tree
      | order: walk |> Enum.with_index() |> Map.new(fn {tag, i} -> {tag.id, i} end),
        states: Map.new(walk, &{&1.id, effective(tree, &1)})
    }
  end

  def get(%__MODULE__{by_id: by_id}, id), do: Map.get(by_id, id)

  @doc "Children of a tag id, or the roots for `nil`, in sibling order."
  def children(%__MODULE__{children: children}, parent_id), do: Map.get(children, parent_id, [])

  @doc "Every tag in display order: each tag before its children."
  def all(%__MODULE__{} = tree), do: depth_first(tree, nil)

  @doc "The tag and all its descendants, in display order."
  def subtree(%__MODULE__{} = tree, id) do
    case get(tree, id) do
      nil -> []
      tag -> [tag | depth_first(tree, id)]
    end
  end

  def subtree_ids(tree, id), do: tree |> subtree(id) |> Enum.map(& &1.id)

  @doc "`:active`, `:on_hold`, or `:dropped`; `nil` for an id not in the tree."
  def state(%__MODULE__{states: states}, id), do: Map.get(states, id)

  @doc "Whether the tag shows in lists and pickers: not dropped, nor under a dropped tag."
  def visible?(tree, id), do: state(tree, id) not in [:dropped, nil]

  @doc "Sort key for showing tags in tree order."
  def position(%__MODULE__{order: order}, id), do: Map.get(order, id, map_size(order))

  @doc """
  Whether a task with these effective tag ids is available: none is on
  hold, and not all of them are dropped. Ids not in the tree are ignored.
  """
  def available?(%__MODULE__{} = tree, tag_ids) do
    states = tag_ids |> Enum.map(&state(tree, &1)) |> Enum.reject(&is_nil/1)
    :on_hold not in states and (states == [] or Enum.any?(states, &(&1 != :dropped)))
  end

  defp depth_first(tree, parent_id) do
    Enum.flat_map(children(tree, parent_id), &[&1 | depth_first(tree, &1.id)])
  end

  defp effective(tree, %Tag{} = tag) do
    if dropped_above?(tree, tag.parent_id), do: :dropped, else: tag.state
  end

  defp dropped_above?(_tree, nil), do: false

  defp dropped_above?(tree, id) do
    case get(tree, id) do
      nil -> false
      %Tag{state: :dropped} -> true
      %Tag{parent_id: parent_id} -> dropped_above?(tree, parent_id)
    end
  end
end
