defmodule Marskal.Recurrence do
  @moduledoc """
  Recurrence series and the occurrences that belong to them (ADR 0007).

  An occurrence is a task (projects later) with `series_id` and
  `occurrence_for`, the slot the rule gave it. It keeps that slot when its
  dates move. The occurrences are the series' history.

  A client joins a task to a series only as its first occurrence. The
  server creates every later one; clients get them on pull (ADR 0014).
  `Marskal.Recurrence.Schedule` names the next slot and the dates that
  move with it; this module creates the task for it.

  On completion, resolving the latest occurrence creates the next, in the
  same command. A regular series gets the first slot after now once its
  latest slot has passed (`generate/1`, run each minute by
  `Marskal.Recurrence.GenerateJob`). Slots that passed in between are
  skipped. Neither creates past the end date, the end count, or, in
  regular mode, the cap of 10 open occurrences.

  The latest occurrence is the one created last. In regular mode that is
  also the greatest slot. On completion, finishing early can give the next
  occurrence an earlier slot than the one finished.
  """

  import Ecto.Changeset
  import Ecto.Query
  alias Marskal.Accounts
  alias Marskal.Accounts.User
  alias Marskal.Changes
  alias Marskal.Recurrence.Schedule
  alias Marskal.Recurrence.Series
  alias Marskal.Repo
  alias Marskal.Tags.TaskTag
  alias Marskal.Tasks
  alias Marskal.Tasks.Task

  @open_cap 10

  # A made-up constant fixed by ADR 0014 ("0014" is the ADR number).
  # Changing it would give existing slots new ids, so the generator would
  # create them again.
  @namespace "a5c0ffee-0014-5000-8000-000000000014"

  @doc """
  The id of the occurrence a rule creates for `occurrence_for`: v5 of the
  series id and the instant, so two writers that reach the same slot name
  the same row (ADR 0014).
  """
  def occurrence_id(series_id, %DateTime{} = occurrence_for) do
    at =
      occurrence_for
      |> DateTime.shift_zone!("Etc/UTC")
      |> Map.update!(:microsecond, fn {us, _precision} -> {us, 6} end)
      |> DateTime.to_iso8601()

    Marskal.Uuid.v5(@namespace, "#{String.downcase(series_id)}|#{at}")
  end

  @doc "A live series the user owns."
  def get_series(%User{} = user, id) do
    case Repo.get_owned(Series, user, id) do
      %Series{discarded_at: nil} = series -> series
      _ -> nil
    end
  end

  def create_series(%User{} = user, attrs, command_id) do
    Changes.apply(user, command_id, "recurrence_series", fn ->
      changeset = Series.create_changeset(%Series{}, user, attrs)

      case Repo.insert(changeset) do
        {:ok, series} -> {:ok, series, changeset}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  @doc "Patch any part of the rule, or `stopped_at`, in one command."
  def update_series(%User{} = user, id, attrs, command_id) when is_map(attrs) do
    Changes.apply(user, command_id, "recurrence_series", fn ->
      case get_series(user, id) do
        nil -> {:error, :not_found}
        series -> Changes.commit(Series.update_changeset(series, attrs))
      end
    end)
  end

  def stop_series(user, id, command_id),
    do: update_series(user, id, %{stopped_at: DateTime.utc_now(:second)}, command_id)

  @doc """
  Discards the series. Its occurrences stay, as ordinary tasks that keep
  their `series_id` and slot.
  """
  def delete_series(%User{} = user, id, command_id) do
    Changes.apply(user, command_id, "recurrence_series", fn ->
      case get_series(user, id) do
        nil ->
          {:error, :not_found}

        series ->
          changeset = Series.discard_changeset(series)
          {:ok, Repo.update!(changeset), changeset}
      end
    end)
  end

  @doc """
  Checks a row that joins a series in this change: `series_id` and
  `occurrence_for` come together, once, as the first occurrence of a live
  series of `kind` that has not stopped, and `occurrence_for` is the row's
  anchor date. With `generated: true` the server is creating a later
  occurrence, and only the database constraints apply.
  """
  def validate_occurrence(changeset, user_id, kind, opts \\ []) do
    joining? = changed?(changeset, :series_id) or changed?(changeset, :occurrence_for)

    cond do
      not joining? or opts[:generated] ->
        changeset

      changeset.data.series_id != nil ->
        add_error(changeset, :series_id, "cannot change once set")

      is_nil(get_field(changeset, :series_id)) or is_nil(get_field(changeset, :occurrence_for)) ->
        add_error(changeset, :occurrence_for, "comes with series_id")

      true ->
        validate_slot(changeset, user_id, kind)
    end
    |> check_constraint(:series_id,
      name: :"#{kind}s_occurrence_fixed",
      message: "cannot change once set"
    )
    |> check_constraint(:occurrence_for,
      name: :"#{kind}s_occurrence_shape",
      message: "comes with series_id"
    )
    |> unique_constraint(:occurrence_for,
      name: :"#{kind}s_series_id_occurrence_for_key",
      message: "is already in the series"
    )
    |> foreign_key_constraint(:series_id,
      name: :"#{kind}s_series_id_fkey",
      message: "must be one of your series"
    )
  end

  defp validate_slot(changeset, user_id, kind) do
    series_id = get_field(changeset, :series_id)

    live =
      Repo.one(
        from s in Series,
          where: s.id == ^series_id and s.user_id == ^user_id and is_nil(s.discarded_at)
      )

    case live do
      %Series{kind: ^kind, stopped_at: nil} = series ->
        cond do
          occurrences?(series) ->
            add_error(changeset, :series_id, "already has its first occurrence")

          get_field(changeset, Series.anchor_field(series)) !=
              get_field(changeset, :occurrence_for) ->
            add_error(changeset, :occurrence_for, "must be the #{series.anchor} date")

          true ->
            changeset
        end

      %Series{kind: ^kind} ->
        add_error(changeset, :series_id, "has stopped")

      _ ->
        add_error(changeset, :series_id, "must be one of your series")
    end
  end

  # Discarded ones too: a deleted first occurrence is still the series'
  # history.
  defp occurrences?(%Series{kind: :task, id: id}),
    do: Repo.exists?(from t in Marskal.Tasks.Task, where: t.series_id == ^id)

  defp occurrences?(%Series{kind: :project, id: id}),
    do: Repo.exists?(from p in Marskal.Projects.Project, where: p.series_id == ^id)

  ## Generating occurrences

  @doc "The most open (To-Do) occurrences a regular series has (ADR 0007)."
  def open_cap, do: @open_cap

  @doc """
  Gives each regular series whose latest slot is not after `now` the first
  slot after it. Returns how many occurrences were created.
  """
  def generate(now \\ DateTime.utc_now(:second)) do
    passed =
      from s in Series,
        join: t in Task,
        on: t.series_id == s.id,
        where: s.mode == :regular and s.kind == :task,
        where: is_nil(s.stopped_at) and is_nil(s.discarded_at),
        group_by: s.id,
        having: max(t.occurrence_for) <= ^now,
        select: s.id

    passed
    |> Repo.all()
    |> Enum.count(fn series_id ->
      case generate_series(series_id, now) do
        # Created inside the transaction, so nothing was broadcast yet.
        {:ok, {user, %Task{} = task}} -> Changes.broadcast(user, "task", task.id)
        _ -> false
      end
    end)
  end

  defp generate_series(series_id, now) do
    Repo.transaction(fn ->
      with %Series{} = series <- lock_live(series_id),
           user = Repo.get!(User, series.user_id),
           %DateTime{} = from <- greatest_slot(series),
           true <- not DateTime.after?(from, now),
           true <- open_count(series) < @open_cap,
           %Task{} = latest <- latest(series),
           %DateTime{} = slot <-
             Schedule.first_slot_after(series, from, now, Accounts.timezone(user)) do
        id = occurrence_id(series.id, slot)
        {user, create_occurrence(user, series, latest, slot, Marskal.Uuid.v5(id, "generate"))}
      else
        _ -> nil
      end
    end)
  end

  @doc false
  # Called by `Marskal.Tasks` in the command that resolves `task`. The
  # next occurrence is part of that command, so a replay replays it too.
  def occurrence_resolved(%User{} = user, command_id, %Task{series_id: series_id} = task)
      when is_binary(series_id) do
    with %Series{mode: :on_completion} = series <- lock_live(series_id),
         %Task{id: id} when id == task.id <- latest(series),
         %DateTime{} = slot <-
           Schedule.next_slot(series, task.resolved_at, Accounts.timezone(user)) do
      next_id = occurrence_id(series.id, slot)
      create_occurrence(user, series, task, slot, Marskal.Uuid.v5(command_id, "task|#{next_id}"))
    end

    :ok
  end

  def occurrence_resolved(_user, _command_id, _task), do: :ok

  # Live and not stopped, locked so two writers do not both create the
  # next occurrence.
  defp lock_live(series_id) do
    Repo.one(
      from s in Series,
        where: s.id == ^series_id and is_nil(s.stopped_at) and is_nil(s.discarded_at),
        lock: "FOR UPDATE"
    )
  end

  # Discarded occurrences count: a deleted slot is not stepped from again.
  defp greatest_slot(series) do
    Repo.one(from t in Task, where: t.series_id == ^series.id, select: max(t.occurrence_for))
  end

  defp open_count(series) do
    Repo.aggregate(
      from(t in Task,
        where: t.series_id == ^series.id and t.state == :to_do and is_nil(t.discarded_at)
      ),
      :count
    )
  end

  # The live occurrence created last. With none left, the series has
  # nothing to copy, and creates nothing.
  defp latest(series) do
    Repo.one(
      from t in Task,
        where: t.series_id == ^series.id and is_nil(t.discarded_at),
        order_by: [desc: t.inserted_at, desc: t.occurrence_for],
        limit: 1
    )
  end

  defp create_occurrence(user, series, latest, slot, command_id) do
    id = occurrence_id(series.id, slot)

    cond do
      # A generated id is never created again, discarded or not.
      Repo.exists?(from t in Task, where: t.id == ^id) -> nil
      ended?(series) -> nil
      true -> insert_occurrence(user, series, latest, id, slot, command_id)
    end
  end

  # End count is N generated, including the first and discarded ones.
  defp ended?(%Series{end_count: nil}), do: false

  defp ended?(series) do
    Repo.aggregate(from(t in Task, where: t.series_id == ^series.id), :count) >=
      series.end_count
  end

  defp insert_occurrence(user, series, latest, id, slot, command_id) do
    dates = Schedule.shift_dates(latest, series.anchor, slot, Accounts.timezone(user))
    parent = latest.parent_id && Tasks.get_task(user, latest.parent_id)

    attrs =
      Map.merge(dates, %{
        id: id,
        title: latest.title,
        notes: latest.notes,
        url: latest.url,
        inbox: latest.inbox,
        project_id: latest.project_id,
        parent_id: parent && parent.id,
        deferred_indefinitely: latest.deferred_indefinitely and series.anchor != :defer,
        series_id: series.id,
        occurrence_for: slot
      })
      |> Map.merge(next_to(user, latest, parent))

    {:ok, task} = Tasks.create_task(user, attrs, command_id, generated: true)
    copy_tags(user, latest, task, command_id)
    task
  end

  # Right after the latest among its siblings. When its parent is gone, at
  # the top of its location, placed as a new task would be.
  defp next_to(_user, latest, nil) when not is_nil(latest.parent_id), do: %{}

  defp next_to(user, latest, _parent) do
    {:ok, rank} = Tasks.Outline.rank_after(user, Tasks.Outline.group(latest), latest.id)
    %{rank: rank}
  end

  # A link to a deleted tag is left behind. A merged tag stands for the one
  # it went into, which `Marskal.Tags.tag_task/4` follows.
  defp copy_tags(user, latest, task, command_id) do
    tag_ids =
      Repo.all(
        from l in TaskTag,
          join: tag in assoc(l, :tag),
          where: l.task_id == ^latest.id and is_nil(l.discarded_at),
          where: is_nil(tag.discarded_at) or not is_nil(tag.merged_into_id),
          order_by: [asc: l.inserted_at, asc: l.id],
          select: l.tag_id
      )

    for tag_id <- tag_ids do
      {:ok, _} =
        Marskal.Tags.tag_task(user, task.id, tag_id, Marskal.Uuid.v5(command_id, "tag|#{tag_id}"))
    end
  end
end
