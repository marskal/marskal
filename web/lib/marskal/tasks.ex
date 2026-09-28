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
    |> order_by([t], desc: t.inserted_at, desc: t.id)
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

  def create_task(%User{} = user, attrs, command_id) when is_map(attrs) do
    Changes.apply(user, command_id, "task", fn ->
      changeset = Task.create_changeset(%Task{}, user, attrs)

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
  """
  def update_task(%User{} = user, task_id, attrs, command_id) when is_map(attrs) do
    Changes.apply(user, command_id, "task", fn ->
      case get_task(user, task_id) do
        nil ->
          {:error, :not_found}

        task ->
          changeset = Task.update_changeset(task, attrs)

          case Repo.update(changeset) do
            {:ok, task} -> {:ok, task, changeset}
            {:error, changeset} -> {:error, changeset}
          end
      end
    end)
  end

  @doc """
  Discards the task. Later patches to it are ignored and it leaves every
  view; Done and Dropped are how work normally ends (ADR 0014).
  """
  def delete_task(%User{} = user, task_id, command_id) do
    Changes.apply(user, command_id, "task", fn ->
      case get_task(user, task_id) do
        nil -> {:error, :not_found}
        task -> discard(task)
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

  defp list_visible(user, inbox) do
    Task
    |> where([t], t.user_id == ^user.id and is_nil(t.discarded_at))
    |> where([t], t.inbox == ^inbox and t.state == :to_do)
    |> order_by([t], desc: t.inserted_at, desc: t.id)
    |> Repo.all()
  end
end
