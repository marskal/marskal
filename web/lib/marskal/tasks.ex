defmodule Marskal.Tasks do
  @moduledoc """
  Task capture and the field-patch write path.

  Every accepted action takes a command id. Replaying that id does nothing
  the second time. The change feed records the patch. A discarded task is
  gone to every read and write here (ADR 0014).
  """

  import Ecto.Query
  alias Marskal.Accounts.User
  alias Marskal.Changes
  alias Marskal.Dates
  alias Marskal.Projects.Project
  alias Marskal.Repo
  alias Marskal.Tasks.Outline
  alias Marskal.Tasks.Task

  def list_inbox(%User{} = user), do: list_visible(user, true)

  @doc """
  The open stream: to-do tasks out of the inbox. Tasks that tag state makes
  unavailable (ADR 0005), and deferred ones (ADR 0006), are left out unless
  `unavailable: true`.
  """
  def list_open(%User{} = user, opts \\ []) do
    tasks = list_visible(user, false)

    if Keyword.get(opts, :unavailable, false), do: tasks, else: available(user, tasks)
  end

  defp available(user, tasks) do
    deferred = deferred_ids(user, tasks)

    tasks
    |> Enum.reject(&MapSet.member?(deferred, &1.id))
    |> then(&Marskal.Tags.reject_unavailable(user, &1))
  end

  @doc "A project's to-do tasks, inbox ones included (ADR 0010)."
  def list_project_tasks(%User{} = user, project_id) do
    Task
    |> where([t], t.user_id == ^user.id and is_nil(t.discarded_at))
    |> where([t], t.project_id == ^project_id and t.state == :to_do)
    |> order_by([t], asc: t.rank, asc: t.id)
    |> Repo.all()
  end

  @doc """
  The agenda for `date` in the user's zone: to-do tasks planned that day,
  earliest first (ADR 0006). With `carry_over: true`, tasks planned on
  earlier days and still to do come first. Deferred and unavailable tasks
  are left out unless `unavailable: true`, as in `list_open/2`.
  """
  def list_planned(%User{} = user, %Date{} = date, opts \\ []) do
    {from, until} = Dates.day_bounds(date, user.timezone)

    tasks =
      Task
      |> where([t], t.user_id == ^user.id and is_nil(t.discarded_at) and t.state == :to_do)
      |> where([t], t.planned_at < ^until)
      |> then(fn query ->
        if Keyword.get(opts, :carry_over, false),
          do: query,
          else: where(query, [t], t.planned_at >= ^from)
      end)
      |> order_by([t], asc: t.planned_at, asc: t.inserted_at, asc: t.id)
      |> Repo.all()

    if Keyword.get(opts, :unavailable, false), do: tasks, else: available(user, tasks)
  end

  @doc """
  Ids of the tasks that are deferred now: by their own Defer, or because
  their project is still deferred (ADR 0006).
  """
  def deferred_ids(%User{} = user, tasks, now \\ DateTime.utc_now()) do
    project_ids = tasks |> Enum.map(& &1.project_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    deferred_projects =
      Project
      |> where([p], p.user_id == ^user.id and p.id in ^project_ids)
      |> Repo.all()
      |> Enum.filter(&Dates.deferred?(&1, now))
      |> MapSet.new(& &1.id)

    for task <- tasks,
        Dates.deferred?(task, now) or MapSet.member?(deferred_projects, task.project_id),
        into: MapSet.new(),
        do: task.id
  end

  @doc "A live task the user owns."
  def get_task(%User{} = user, id) do
    case Repo.get_owned(Task, user, id) do
      %Task{discarded_at: nil} = task -> task
      _ -> nil
    end
  end

  @doc "The user's live tasks with these ids, in no particular order."
  def get_tasks(%User{} = user, ids) do
    Task
    |> where([t], t.user_id == ^user.id and t.id in ^ids and is_nil(t.discarded_at))
    |> Repo.all()
  end

  @doc """
  A new task. With `parent_id` it is a subtask and lives where its parent
  does, whatever location is given. With `after_id` it goes right after
  that sibling; otherwise at the top of the inbox or the bottom of
  anywhere else. A `rank` from a client is kept as given.
  """
  def create_task(%User{} = user, attrs, command_id) when is_map(attrs) do
    Changes.apply(user, command_id, "task", fn ->
      changeset =
        %Task{}
        |> Task.create_changeset(user, attrs)
        |> place_new(user, attr(attrs, :after_id))

      case Repo.insert(changeset) do
        {:ok, task} -> {:ok, task, changeset}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  @doc """
  Patch any of title, notes, project_id, inbox, state, and the dates in one
  command. Fields equal to the stored value are left out of the patch,
  except that a move always carries both inbox and project_id (ADR 0017),
  and a Defer change both of its fields (ADR 0006).

  A move to another location takes the task out from under its parent,
  and its subtasks go with it.
  """
  def update_task(%User{} = user, task_id, attrs, command_id) when is_map(attrs) do
    Changes.apply(user, command_id, "task", fn ->
      case get_task(user, task_id) do
        nil ->
          {:error, :not_found}

        task ->
          changeset = task |> Task.update_changeset(attrs) |> detach_on_move(user, task)
          write_with_subtree(user, command_id, changeset)
      end
    end)
  end

  @doc """
  Places a task in the outline: under `parent_id` (`nil` for the top of its
  location), right after the sibling `after_id` (`nil` for first). At the
  top, the task stays in its location unless `after_id` names a task in
  another one. Its subtasks come along.
  """
  def place_task(%User{} = user, task_id, parent_id, after_id, command_id) do
    Changes.apply(user, command_id, "task", fn ->
      case get_task(user, task_id) do
        nil -> {:error, :not_found}
        task -> place(user, command_id, task, parent_id, after_id)
      end
    end)
  end

  @doc "Makes the task the last subtask of the sibling above it."
  def indent_task(%User{} = user, task_id, command_id) do
    Changes.apply(user, command_id, "task", fn ->
      with %Task{} = task <- get_task(user, task_id) || {:error, :not_found},
           %Task{} = above <- Outline.previous_sibling(user, task) || {:error, :first} do
        last = Outline.last_child(user, above)
        place(user, command_id, task, above.id, last && last.id)
      end
    end)
  end

  @doc "Moves the task out of its parent, to just after it."
  def outdent_task(%User{} = user, task_id, command_id) do
    Changes.apply(user, command_id, "task", fn ->
      with %Task{} = task <- get_task(user, task_id) || {:error, :not_found},
           %Task{} = parent <- parent(user, task) || {:error, :top_level} do
        place(user, command_id, task, parent.parent_id, parent.id)
      end
    end)
  end

  @doc """
  Discards the task and its subtasks. Later patches to them are ignored
  and they leave every view; Done and Dropped are how work normally ends
  (ADR 0014).
  """
  def delete_task(%User{} = user, task_id, command_id) do
    Changes.apply(user, command_id, "task", fn ->
      case get_task(user, task_id) do
        nil -> {:error, :not_found}
        task -> discard_subtree(user, command_id, task)
      end
    end)
  end

  @doc false
  def discard(%Task{} = task) do
    changeset = Task.discard_changeset(task)
    {:ok, Repo.update!(changeset), changeset}
  end

  def rename_task(user, task_id, title, command_id),
    do: update_task(user, task_id, %{title: title}, command_id)

  @doc """
  Moves a task to the inbox (`:inbox`), out of everything (`:none`), or into
  a project (its id). The three are one location (ADR 0017).
  """
  def move_task(user, task_id, location, command_id),
    do: update_task(user, task_id, location_attrs(location), command_id)

  @doc "The inbox and project_id fields for a location."
  def location_attrs(:inbox), do: %{inbox: true, project_id: nil}
  def location_attrs(:none), do: %{inbox: false, project_id: nil}

  def location_attrs(project_id) when is_binary(project_id),
    do: %{inbox: false, project_id: project_id}

  @doc "A task's location: `:inbox`, `:none`, or its project id."
  def location(%Task{inbox: true}), do: :inbox
  def location(%Task{project_id: nil}), do: :none
  def location(%Task{project_id: project_id}), do: project_id

  def complete_task(user, task_id, command_id),
    do: update_task(user, task_id, %{state: :done}, command_id)

  def drop_task(user, task_id, command_id),
    do: update_task(user, task_id, %{state: :dropped}, command_id)

  def reopen_task(user, task_id, command_id),
    do: update_task(user, task_id, %{state: :to_do}, command_id)

  def set_notes(user, task_id, notes, command_id),
    do: update_task(user, task_id, %{notes: notes}, command_id)

  ## Outline

  defp parent(_user, %Task{parent_id: nil}), do: nil
  defp parent(user, %Task{parent_id: id}), do: get_task(user, id)

  defp place(user, command_id, task, parent_id, after_id) do
    with {:ok, group} <- target_group(user, task, parent_id, after_id),
         {:ok, rank} <- Outline.rank_after(user, group, after_id, task.id) do
      changeset = Task.place_changeset(task, Map.put(group, :rank, rank))
      write_with_subtree(user, command_id, changeset)
    end
  end

  defp target_group(_user, task, nil, nil), do: {:ok, %{Outline.group(task) | parent_id: nil}}

  # At the top, the sibling to follow says which location.
  defp target_group(user, _task, nil, after_id) do
    case get_task(user, after_id) do
      nil -> {:error, :not_a_sibling}
      after_task -> {:ok, %{Outline.group(after_task) | parent_id: nil}}
    end
  end

  defp target_group(user, task, parent_id, _after_id) do
    case get_task(user, parent_id) do
      nil ->
        {:error, :not_found}

      parent ->
        if Outline.within?(parent, task.id),
          do: {:error, :cycle},
          else: {:ok, Outline.children_of(parent)}
    end
  end

  # A new subtask lives where its parent does. Ranks from a client stand.
  defp place_new(%Ecto.Changeset{valid?: false} = changeset, _user, _after_id), do: changeset

  defp place_new(changeset, user, after_id) do
    changeset =
      case Ecto.Changeset.get_field(changeset, :parent_id) do
        nil ->
          changeset

        parent_id ->
          case get_task(user, parent_id) do
            nil ->
              Ecto.Changeset.add_error(changeset, :parent_id, "must be one of your tasks")

            parent ->
              changeset
              |> Ecto.Changeset.force_change(:inbox, parent.inbox)
              |> Ecto.Changeset.force_change(:project_id, parent.project_id)
          end
      end

    cond do
      not changeset.valid? ->
        changeset

      Ecto.Changeset.get_change(changeset, :rank) ->
        changeset

      true ->
        group = Outline.group(Ecto.Changeset.apply_changes(changeset))

        case new_rank(user, group, after_id) do
          {:ok, rank} -> Ecto.Changeset.put_change(changeset, :rank, rank)
          {:error, _} -> Ecto.Changeset.add_error(changeset, :after_id, "must be a sibling")
        end
    end
  end

  defp new_rank(user, group, nil), do: {:ok, Outline.default_rank(user, group)}
  defp new_rank(user, group, after_id), do: Outline.rank_after(user, group, after_id)

  # Moving to another location leaves the parent behind: the task goes to
  # the top of the new location, placed as a new task would be.
  defp detach_on_move(%Ecto.Changeset{valid?: false} = changeset, _user, _task), do: changeset

  defp detach_on_move(changeset, user, task) do
    moved = Outline.group(Ecto.Changeset.apply_changes(changeset))

    if moved.inbox == task.inbox and moved.project_id == task.project_id do
      changeset
    else
      group = %{moved | parent_id: nil}

      changeset
      |> Ecto.Changeset.put_change(:parent_id, nil)
      |> Ecto.Changeset.put_change(:rank, Outline.default_rank(user, group, task.id))
    end
  end

  defp write_with_subtree(user, command_id, changeset) do
    case Repo.update(changeset) do
      {:ok, task} ->
        if Ecto.Changeset.changed?(changeset, :inbox) or
             Ecto.Changeset.changed?(changeset, :project_id) do
          relocate_subtree(user, command_id, task)
        end

        {:ok, task, changeset}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Subtasks follow their parent to its new location, one command each.
  defp relocate_subtree(user, command_id, task) do
    for child <- Outline.children(task) do
      Changes.cascade(user, command_id, "task", child.id, fn ->
        changeset = Task.relocate_changeset(child, task.inbox, task.project_id)
        moved = Repo.update!(changeset)
        relocate_subtree(user, command_id, moved)
        {:ok, moved, changeset}
      end)
    end
  end

  defp discard_subtree(user, command_id, task) do
    for child <- Outline.children(task) do
      Changes.cascade(user, command_id, "task", child.id, fn ->
        discard_subtree(user, command_id, child)
      end)
    end

    discard(task)
  end

  # Forms send a blank for none.
  defp attr(attrs, key) do
    case Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key)) do
      "" -> nil
      value -> value
    end
  end

  # The inbox is a location, in outline order. The open stream gathers
  # every location, newest first.
  defp list_visible(user, inbox) do
    Task
    |> where([t], t.user_id == ^user.id and is_nil(t.discarded_at))
    |> where([t], t.inbox == ^inbox and t.state == :to_do)
    |> then(fn query ->
      if inbox,
        do: order_by(query, [t], asc: t.rank, asc: t.id),
        else: order_by(query, [t], desc: t.inserted_at, desc: t.id)
    end)
    |> Repo.all()
  end
end
