defmodule Marskal.Tasks.Outline do
  @moduledoc """
  Where a task sits in the outline (ADR 0009): its parent and its rank
  among siblings (ADR 0014).

  Siblings share a parent, or, at the top, a location. A subtask always
  lives where its parent does, so a group is the parent and the location
  together:

      %{parent_id: nil | id, inbox: boolean, project_id: nil | id}

  Every rank here is worked out from the siblings as they are when the
  write runs, so a neighbor that moved in the meantime cannot make two
  ranks collide.
  """

  import Ecto.Query
  alias Marskal.Rank
  alias Marskal.Repo
  alias Marskal.Tasks.Task

  @doc "The sibling group a task is in."
  def group(%{parent_id: parent_id, inbox: inbox, project_id: project_id}),
    do: %{parent_id: parent_id, inbox: inbox, project_id: project_id}

  @doc "The group of a parent's subtasks."
  def children_of(%Task{} = parent), do: %{group(parent) | parent_id: parent.id}

  @doc """
  The rank for a new task placed by default: the top of the inbox, since
  it lists newest first, and the bottom everywhere else.
  """
  def default_rank(user, group, except \\ nil)

  def default_rank(user, %{parent_id: nil, inbox: true} = group, except),
    do: Rank.between(nil, first_rank(user, group, except))

  def default_rank(user, group, except),
    do: Rank.between(last_rank(user, group, except), nil)

  @doc """
  The rank right after sibling `after_id`, or first in the group for `nil`.
  `except` is the task being placed, left out of its own neighbors.
  """
  def rank_after(user, group, after_id, except \\ nil)

  def rank_after(user, group, nil, except),
    do: {:ok, Rank.between(nil, first_rank(user, group, except))}

  def rank_after(user, group, after_id, except) do
    case sibling(user, group, after_id) do
      %Task{id: ^except} ->
        {:error, :not_a_sibling}

      %Task{rank: rank} ->
        next =
          user
          |> siblings(group, except)
          |> where([t], t.rank > ^rank)
          |> select([t], min(t.rank))
          |> Repo.one()

        {:ok, Rank.between(rank, next)}

      nil ->
        {:error, :not_a_sibling}
    end
  end

  @doc "The sibling just before `task`, if there is one."
  def previous_sibling(user, %Task{} = task) do
    user
    |> siblings(group(task), task.id)
    |> where([t], t.rank < ^task.rank)
    |> order_by([t], desc: t.rank, desc: t.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc "The sibling just after `task`, if there is one."
  def next_sibling(user, %Task{} = task) do
    user
    |> siblings(group(task), task.id)
    |> where([t], t.rank > ^task.rank)
    |> order_by([t], asc: t.rank, asc: t.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc "The last subtask of `parent`, if it has any."
  def last_child(user, %Task{} = parent) do
    user
    |> siblings(children_of(parent), nil)
    |> order_by([t], desc: t.rank, desc: t.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc "A live task's live subtasks, in order."
  def children(%Task{} = task) do
    Task
    |> where([t], t.parent_id == ^task.id and is_nil(t.discarded_at))
    |> order_by([t], asc: t.rank, asc: t.id)
    |> Repo.all()
  end

  @doc "True when `task` is the task `ancestor_id`, or lies under it."
  def within?(%Task{id: id}, id), do: true
  def within?(%Task{parent_id: nil}, _ancestor_id), do: false

  def within?(%Task{parent_id: parent_id}, ancestor_id),
    do: parent_id == ancestor_id or within?(Repo.get!(Task, parent_id), ancestor_id)

  defp sibling(user, group, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> user |> siblings(group, nil) |> where([t], t.id == ^id) |> Repo.one()
      :error -> nil
    end
  end

  defp first_rank(user, group, except),
    do: user |> siblings(group, except) |> select([t], min(t.rank)) |> Repo.one()

  defp last_rank(user, group, except),
    do: user |> siblings(group, except) |> select([t], max(t.rank)) |> Repo.one()

  defp siblings(user, group, except) do
    Task
    |> where([t], t.user_id == ^user.id and is_nil(t.discarded_at))
    |> where_group(group)
    |> then(fn query -> if except, do: where(query, [t], t.id != ^except), else: query end)
  end

  # Subtasks share a location with their parent, so the parent alone
  # picks out the group.
  defp where_group(query, %{parent_id: nil, inbox: inbox, project_id: nil}),
    do: where(query, [t], is_nil(t.parent_id) and t.inbox == ^inbox and is_nil(t.project_id))

  defp where_group(query, %{parent_id: nil, project_id: project_id}),
    do: where(query, [t], is_nil(t.parent_id) and t.project_id == ^project_id)

  defp where_group(query, %{parent_id: parent_id}),
    do: where(query, [t], t.parent_id == ^parent_id)
end
