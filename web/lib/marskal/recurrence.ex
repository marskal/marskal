defmodule Marskal.Recurrence do
  @moduledoc """
  Recurrence series and the occurrences that belong to them (ADR 0007).

  An occurrence is a task or a project, as the series' `kind` says, with
  `series_id` and `occurrence_for`, the slot the rule gave it. It keeps
  that slot when its dates move. The occurrences are the series' history.

  A client joins a task or project to a series only as its first
  occurrence. The server creates every later one; clients get them on
  pull (ADR 0014). `Marskal.Recurrence.Schedule` names the next slot and
  the dates that move with it; this module creates the occurrence for it,
  with the latest's tasks copied under it.

  A series has one occurrence at a time: resolving the latest, Done or
  Dropped, creates the next, in the same command. Regular mode takes the
  slot after the one resolved, or, when that has passed, the first slot
  after the resolution; the slots in between are skipped. On completion
  counts the interval from the resolution. Neither creates past the end
  date or the end count. Resuming a paused series whose latest was
  resolved creates the next from then. Deleting the latest ends the
  series; Dropped is how to skip one.

  The latest occurrence is the one created last. On completion,
  finishing early can give the next occurrence an earlier slot than the
  one finished.
  """

  import Ecto.Changeset
  import Ecto.Query
  alias Marskal.Accounts
  alias Marskal.Accounts.User
  alias Marskal.Changes
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.Projects
  alias Marskal.Projects.Project
  alias Marskal.Recurrence.History
  alias Marskal.Recurrence.Schedule
  alias Marskal.Recurrence.Series
  alias Marskal.Repo
  alias Marskal.Tags.ProjectTag
  alias Marskal.Tags.TaskTag
  alias Marskal.Tasks
  alias Marskal.Tasks.Task

  # A made-up constant fixed by ADR 0014 ("0014" is the ADR number).
  # Changing it would give existing slots new ids, so a slot already
  # created could be created again.
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

  @doc """
  Makes `task` the first occurrence of a new series with the rule in
  `attrs`, in one command. The task must not be in a series already.

  `starts_at:` sets the task's anchor date to that instant, as the first
  slot. Without it, the task needs the anchor date already.
  """
  def repeat_task(%User{} = user, task_id, attrs, command_id, opts \\ [])
      when is_map(attrs),
      do: repeat(user, :task, task_id, attrs, command_id, opts)

  @doc "As `repeat_task/5`, for a project."
  def repeat_project(%User{} = user, project_id, attrs, command_id, opts \\ [])
      when is_map(attrs),
      do: repeat(user, :project, project_id, attrs, command_id, opts)

  defp repeat(user, kind, id, attrs, command_id, opts) do
    Changes.apply(user, command_id, "recurrence_series", fn ->
      case get_record(user, kind, id) do
        nil ->
          {:error, :not_found}

        %{series_id: nil} = record ->
          start_series(user, kind, record, attrs, command_id, opts[:starts_at])

        _record ->
          {:error, :already_repeating}
      end
    end)
  end

  defp get_record(user, :task, id), do: Tasks.get_task(user, id)
  defp get_record(user, :project, id), do: Projects.get_project(user, id)

  defp schema(:task), do: Task
  defp schema(:project), do: Project

  defp start_series(user, kind, record, attrs, command_id, starts_at) do
    changeset =
      %Series{}
      |> Series.create_changeset(user, Map.put(stringify(attrs), "kind", to_string(kind)))
      |> require_anchor_date(kind, record, starts_at)

    with {:ok, series} <- Repo.insert(changeset),
         {:ok, _record} <- join_series(user, kind, record, series, starts_at, command_id) do
      {:ok, series, changeset}
    end
  end

  defp stringify(attrs), do: Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

  defp require_anchor_date(%Ecto.Changeset{valid?: false} = changeset, _kind, _record, _at),
    do: changeset

  defp require_anchor_date(changeset, _kind, _record, %DateTime{}), do: changeset

  defp require_anchor_date(changeset, kind, record, nil) do
    series = apply_changes(changeset)

    if Map.fetch!(record, Series.anchor_field(series)),
      do: changeset,
      else:
        add_error(changeset, :anchor, "needs the #{kind}'s #{anchor_word(series.anchor)} date")
  end

  defp anchor_word(:defer), do: "Defer"
  defp anchor_word(:planned), do: "Planned"
  defp anchor_word(:due), do: "Due"

  # The join follows from the series insert, with its own derived command.
  defp join_series(user, kind, record, series, starts_at, command_id) do
    field = Series.anchor_field(series)
    slot = DateTime.truncate(starts_at || Map.fetch!(record, field), :second)
    attrs = %{field => slot, series_id: series.id, occurrence_for: slot}

    attrs =
      if field == :defer_until, do: Map.put(attrs, :deferred_indefinitely, false), else: attrs

    join_command = Marskal.Uuid.v5(command_id, "#{kind}|#{record.id}")

    case kind do
      :task -> Tasks.update_task(user, record.id, attrs, join_command)
      :project -> Projects.update_project(user, record.id, attrs, join_command)
    end
  end

  @doc "The live occurrence of a task's or project's series with the slot just before it."
  def previous_occurrence(%User{} = user, %schema{series_id: id, occurrence_for: slot})
      when is_binary(id) and schema in [Task, Project] do
    Repo.one(
      from r in schema,
        where: r.user_id == ^user.id and r.series_id == ^id and is_nil(r.discarded_at),
        where: r.occurrence_for < ^slot,
        order_by: [desc: r.occurrence_for],
        limit: 1
    )
  end

  def previous_occurrence(_user, _record), do: nil

  @doc """
  The next `count` slots after `from`, in regular mode. Fewer when the rule
  ends first; none on completion, where they depend on when each is done.
  """
  def upcoming(%Series{mode: :regular} = series, %DateTime{} = from, zone, count) do
    from
    |> Stream.unfold(fn at ->
      case Schedule.next_slot(series, at, zone) do
        nil -> nil
        slot -> {slot, slot}
      end
    end)
    |> Enum.take(count)
  end

  def upcoming(_series, _from, _zone, _count), do: []

  @doc "The greatest slot among the series' live occurrences."
  def latest_slot(%Series{} = series) do
    Repo.one(
      from r in schema(series.kind),
        where: r.series_id == ^series.id and is_nil(r.discarded_at),
        select: max(r.occurrence_for)
    )
  end

  @doc """
  The series' history as of `now`: its live occurrences with the slots
  missed and paused between them, and the numbers worked out from them
  (`Marskal.Recurrence.History`).
  """
  def history(%User{} = user, %Series{} = series, now \\ DateTime.utc_now()) do
    occurrences =
      Repo.all(
        from r in schema(series.kind),
          where: r.user_id == ^user.id and r.series_id == ^series.id and is_nil(r.discarded_at),
          order_by: [asc: r.occurrence_for]
      )

    History.build(series, occurrences, now, Accounts.timezone(user))
  end

  @doc "Which of these tasks or projects are in a live series that has not stopped."
  def repeating_ids(%User{} = user, records) do
    case for %{series_id: id} when is_binary(id) <- records, do: id do
      [] ->
        MapSet.new()

      series_ids ->
        live =
          Repo.all(
            from s in Series,
              where: s.user_id == ^user.id and s.id in ^Enum.uniq(series_ids),
              where: is_nil(s.stopped_at) and is_nil(s.discarded_at),
              select: s.id
          )
          |> MapSet.new()

        for %{series_id: id} = record <- records,
            MapSet.member?(live, id),
            into: MapSet.new(),
            do: record.id
    end
  end

  @doc "Patch any part of the rule, or `stopped_at`, in one command."
  def update_series(%User{} = user, id, attrs, command_id) when is_map(attrs) do
    Changes.apply(user, command_id, "recurrence_series", fn ->
      case get_series(user, id) do
        nil -> {:error, :not_found}
        series -> commit_update(user, series, attrs, command_id)
      end
    end)
  end

  defp commit_update(user, series, attrs, command_id) do
    with {:ok, updated, changeset} <- Changes.commit(Series.update_changeset(series, attrs)) do
      if series.stopped_at && is_nil(updated.stopped_at), do: resumed(user, updated, command_id)
      {:ok, updated, changeset}
    end
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
          discard_series(series)
      end
    end)
  end

  defp discard_series(series) do
    changeset = Series.discard_changeset(series)
    {:ok, Repo.update!(changeset), changeset}
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

  ## Creating occurrences

  @doc false
  # Called by `Marskal.Tasks` or `Marskal.Projects` in the command that
  # resolves `record`. The next occurrence is part of that command, so a
  # replay replays it too.
  def occurrence_resolved(%User{} = user, command_id, %{series_id: series_id} = record)
      when is_binary(series_id) do
    with %Series{} = series <- lock_live(series_id),
         %{id: id} when id == record.id <- latest(series) do
      create_next(user, series, record, record.resolved_at, command_id)
    end

    :ok
  end

  def occurrence_resolved(_user, _command_id, _record), do: :ok

  @doc false
  # Called by `Marskal.Tasks` or `Marskal.Projects` in the command that
  # deletes `record`, before the discard. Deleting the latest occurrence
  # ends its series, paused or not; the occurrences before it stay, as
  # `delete_series/3` leaves them.
  def occurrence_deleted(%User{} = user, command_id, %{series_id: series_id} = record)
      when is_binary(series_id) do
    with %Series{} = series <- lock_series(series_id),
         %{id: id} when id == record.id <- latest(series) do
      Changes.cascade(user, command_id, "recurrence_series", series.id, fn ->
        discard_series(series)
      end)
    end

    :ok
  end

  def occurrence_deleted(_user, _command_id, _record), do: :ok

  # A series paused after its latest was resolved made nothing then. On
  # resume it steps on from now.
  defp resumed(user, series, command_id) do
    with %Series{} = series <- lock_live(series.id),
         %{state: state} = latest when state != :to_do <- latest(series) do
      create_next(user, series, latest, DateTime.utc_now(:second), command_id)
    end
  end

  # Regular mode steps on from the slot resolved, past any slot before
  # `at`. On completion counts the interval from `at`.
  defp create_next(user, series, latest, at, command_id) do
    zone = Accounts.timezone(user)

    slot =
      case series.mode do
        :regular -> Schedule.first_slot_after(series, latest.occurrence_for, at, zone)
        :on_completion -> Schedule.next_slot(series, at, zone)
      end

    if slot do
      next_id = occurrence_id(series.id, slot)

      create_occurrence(
        user,
        series,
        latest,
        slot,
        Marskal.Uuid.v5(command_id, "#{series.kind}|#{next_id}")
      )
    end
  end

  # Live and not stopped, locked so two writers do not both create the
  # next occurrence.
  defp lock_live(series_id) do
    case lock_series(series_id) do
      %Series{stopped_at: nil} = series -> series
      _ -> nil
    end
  end

  defp lock_series(series_id) do
    Repo.one(
      from s in Series,
        where: s.id == ^series_id and is_nil(s.discarded_at),
        lock: "FOR UPDATE"
    )
  end

  # The live occurrence created last. With none left, the series has
  # nothing to copy, and creates nothing.
  defp latest(series) do
    Repo.one(
      from r in schema(series.kind),
        where: r.series_id == ^series.id and is_nil(r.discarded_at),
        order_by: [desc: r.inserted_at, desc: r.occurrence_for],
        limit: 1
    )
  end

  defp create_occurrence(user, series, latest, slot, command_id) do
    id = occurrence_id(series.id, slot)

    cond do
      # A generated id is never created again, discarded or not.
      Repo.exists?(from r in schema(series.kind), where: r.id == ^id) -> nil
      ended?(series) -> nil
      true -> insert_occurrence(user, series, latest, id, slot, command_id)
    end
  end

  # End count is N generated, including the first and discarded ones.
  defp ended?(%Series{end_count: nil}), do: false

  defp ended?(series) do
    Repo.aggregate(from(r in schema(series.kind), where: r.series_id == ^series.id), :count) >=
      series.end_count
  end

  defp insert_occurrence(user, %Series{kind: :task} = series, latest, id, slot, command_id) do
    dates = Schedule.shift_dates(latest, series.anchor, slot, Accounts.timezone(user))
    parent = latest.parent_id && Tasks.get_task(user, latest.parent_id)

    attrs =
      Map.merge(dates, %{
        id: id,
        title: latest.title,
        notes: latest.notes,
        url: latest.url,
        flagged: latest.flagged,
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
    anchor_at = Map.fetch!(latest, Series.anchor_field(series))
    copy = {task.id, anchor_at, slot}
    copy_tasks(user, Tasks.Outline.children(latest), %{parent_id: task.id}, copy, command_id)
    task
  end

  # A project copies the latest's folder, while the folder is live, its
  # tags, and its live tasks, as a task copies its subtasks.
  defp insert_occurrence(user, %Series{kind: :project} = series, latest, id, slot, command_id) do
    dates = Schedule.shift_dates(latest, series.anchor, slot, Accounts.timezone(user))

    attrs =
      Map.merge(dates, %{
        id: id,
        title: latest.title,
        notes: latest.notes,
        url: latest.url,
        flagged: latest.flagged,
        project_folder_id: live_folder_id(latest),
        deferred_indefinitely: latest.deferred_indefinitely and series.anchor != :defer,
        series_id: series.id,
        occurrence_for: slot
      })

    {:ok, project} = Projects.create_project(user, attrs, command_id, generated: true)
    copy_project_tags(user, latest, project, command_id)
    anchor_at = Map.fetch!(latest, Series.anchor_field(series))
    place = %{project_id: project.id, inbox: false, parent_id: nil}
    copy_tasks(user, top_tasks(latest), place, {project.id, anchor_at, slot}, command_id)
    project
  end

  defp live_folder_id(%Project{project_folder_id: nil}), do: nil

  defp live_folder_id(%Project{project_folder_id: id}) do
    case Repo.get(ProjectFolder, id) do
      %ProjectFolder{discarded_at: nil} -> id
      _ -> nil
    end
  end

  defp top_tasks(project) do
    Repo.all(
      from t in Task,
        where: t.project_id == ^project.id and is_nil(t.parent_id) and is_nil(t.discarded_at),
        order_by: [asc: t.rank, asc: t.id]
    )
  end

  # Copies `tasks` into the new occurrence at `place`, with the live
  # subtasks under them, in the same order, every one To-Do, Dropped ones
  # too. A copy's id is v5 of the new occurrence and the task copied, so
  # the tree has one name wherever it is made. Dates keep their distance
  # from the anchor. A task in a series of its own is copied as a plain
  # task.
  defp copy_tasks(user, tasks, place, {occurrence_id, anchor_at, slot} = copy, command_id) do
    zone = Accounts.timezone(user)

    for source <- tasks do
      id = Marskal.Uuid.v5(occurrence_id, source.id)
      task_command = Marskal.Uuid.v5(command_id, "task|#{id}")

      attrs =
        source
        |> Schedule.shift_subtask_dates(anchor_at, slot, zone)
        |> Map.merge(%{
          id: id,
          title: source.title,
          notes: source.notes,
          url: source.url,
          flagged: source.flagged,
          rank: source.rank,
          deferred_indefinitely: source.deferred_indefinitely
        })
        |> Map.merge(place)

      {:ok, task} = Tasks.create_task(user, attrs, task_command)
      copy_tags(user, source, task, task_command)
      copy_tasks(user, Tasks.Outline.children(source), %{parent_id: task.id}, copy, command_id)
    end
  end

  # Right after the latest among its siblings. When its parent is gone, at
  # the top of its location, placed as a new task would be.
  defp next_to(_user, latest, nil) when not is_nil(latest.parent_id), do: %{}

  defp next_to(user, latest, _parent) do
    {:ok, rank} = Tasks.Outline.rank_after(user, Tasks.Outline.group(latest), latest.id)
    %{rank: rank}
  end

  # A link to a deleted tag is left behind. A merged tag stands for the one
  # it went into, which `Marskal.Tags` follows.
  defp copy_tags(user, %Task{} = source, %Task{} = copy, command_id) do
    for tag_id <- live_tag_ids(TaskTag, :task_id, source.id) do
      {:ok, _} =
        Marskal.Tags.tag_task(user, copy.id, tag_id, Marskal.Uuid.v5(command_id, "tag|#{tag_id}"))
    end
  end

  defp copy_project_tags(user, source, copy, command_id) do
    for tag_id <- live_tag_ids(ProjectTag, :project_id, source.id) do
      {:ok, _} =
        Marskal.Tags.tag_project(
          user,
          copy.id,
          tag_id,
          Marskal.Uuid.v5(command_id, "tag|#{tag_id}")
        )
    end
  end

  defp live_tag_ids(schema, owner_field, owner_id) do
    Repo.all(
      from l in schema,
        join: tag in assoc(l, :tag),
        where: field(l, ^owner_field) == ^owner_id and is_nil(l.discarded_at),
        where: is_nil(tag.discarded_at) or not is_nil(tag.merged_into_id),
        order_by: [asc: l.inserted_at, asc: l.id],
        select: l.tag_id
    )
  end
end
