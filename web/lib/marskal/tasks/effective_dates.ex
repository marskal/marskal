defmodule Marskal.Tasks.EffectiveDates do
  @moduledoc """
  The dates a task goes by (ADR 0006, ADR 0009). A task with no Planned or
  Due of its own takes its parent's, and a top-level task its project's,
  so a date set on a parent reaches the whole subtree.

  Defer is the stronger of the two: a task is deferred while anything
  above it is, even when it has an earlier Defer of its own, since it
  should not surface before what contains it.

  These are derived, like `parent_path` on tags: worked out at read time,
  never written or synced (ADR 0014).
  """

  import Ecto.Query
  alias Marskal.Projects.Project
  alias Marskal.Repo
  alias Marskal.Tasks.Task

  @name "task_dates"

  @doc """
  Adds the `task_dates` CTE to `query`, one row per live task of the user:
  `id`, `defer_until`, `deferred_indefinitely`, `planned_at`, `due_at`.
  Join it by id.
  """
  def with_dates(query, user) do
    query
    |> recursive_ctes(true)
    |> with_cte(@name, as: ^cte(user))
  end

  def name, do: @name

  @doc "The effective dates of these tasks, by id."
  def for_tasks(_user, []), do: %{}

  def for_tasks(user, tasks) do
    ids = Enum.map(tasks, & &1.id)

    from(d in @name,
      where: d.id in type(^ids, {:array, Ecto.UUID}),
      select:
        {type(d.id, Ecto.UUID),
         %{
           defer_until: type(d.defer_until, :utc_datetime),
           deferred_indefinitely: d.deferred_indefinitely,
           planned_at: type(d.planned_at, :utc_datetime),
           due_at: type(d.due_at, :utc_datetime)
         }}
    )
    |> with_dates(user)
    |> Repo.all()
    |> Map.new()
  end

  # Top-level tasks start from their project; each subtask starts from its
  # parent's row. GREATEST ignores NULLs, so Defer keeps the latest.
  defp cte(user) do
    top =
      from t in Task,
        left_join: p in Project,
        on: p.id == t.project_id,
        where: t.user_id == ^user.id and is_nil(t.parent_id) and is_nil(t.discarded_at),
        select: %{
          id: t.id,
          defer_until: fragment("GREATEST(?, ?)", t.defer_until, p.defer_until),
          deferred_indefinitely:
            t.deferred_indefinitely or coalesce(p.deferred_indefinitely, false),
          planned_at: coalesce(t.planned_at, p.planned_at),
          due_at: coalesce(t.due_at, p.due_at)
        }

    below =
      from t in Task,
        join: d in @name,
        on: t.parent_id == d.id,
        where: is_nil(t.discarded_at),
        select: %{
          id: t.id,
          defer_until: fragment("GREATEST(?, ?)", t.defer_until, d.defer_until),
          deferred_indefinitely: t.deferred_indefinitely or d.deferred_indefinitely,
          planned_at: coalesce(t.planned_at, d.planned_at),
          due_at: coalesce(t.due_at, d.due_at)
        }

    union_all(top, ^below)
  end
end
