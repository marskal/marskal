defmodule Marskal.Tasks do
  @moduledoc """
  Task capture and the field-patch write path.

  Every accepted action takes a command id. Replaying that id does nothing
  the second time. The change feed records the patch.
  """

  import Ecto.Query
  alias Marskal.Accounts.User
  alias Marskal.Changes
  alias Marskal.Repo
  alias Marskal.Tasks.Task

  def list_inbox(%User{} = user), do: list_visible(user, true)

  @doc """
  The open stream: clarified to-do tasks. Tasks that tag state makes
  unavailable (ADR 0005) are left out unless `unavailable: true`.
  """
  def list_open(%User{} = user, opts \\ []) do
    tasks = list_visible(user, false)

    if Keyword.get(opts, :unavailable, false),
      do: tasks,
      else: Marskal.Tags.reject_unavailable(user, tasks)
  end

  @doc "A project's to-do tasks, inbox ones included (ADR 0010)."
  def list_project_tasks(%User{} = user, project_id) do
    Task
    |> where(
      [t],
      t.user_id == ^user.id and t.project_id == ^project_id and t.state == :to_do
    )
    |> order_by([t], desc: t.inserted_at, desc: t.id)
    |> Repo.all()
  end

  def get_task(%User{} = user, id), do: Repo.get_owned(Task, user, id)

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
  Patch any of title, notes, project_id, inbox, and state in one command.
  Fields equal to the stored value are left out of the patch.
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

  def rename_task(user, task_id, title, command_id),
    do: update_task(user, task_id, %{title: title}, command_id)

  def clarify_task(user, task_id, command_id),
    do: update_task(user, task_id, %{inbox: false}, command_id)

  def set_inbox(user, task_id, inbox, command_id) when is_boolean(inbox),
    do: update_task(user, task_id, %{inbox: inbox}, command_id)

  def complete_task(user, task_id, command_id),
    do: update_task(user, task_id, %{state: :done}, command_id)

  def drop_task(user, task_id, command_id),
    do: update_task(user, task_id, %{state: :dropped}, command_id)

  def reopen_task(user, task_id, command_id),
    do: update_task(user, task_id, %{state: :to_do}, command_id)

  def set_notes(user, task_id, notes, command_id),
    do: update_task(user, task_id, %{notes: notes}, command_id)

  def file_task(user, task_id, project_id, command_id),
    do: update_task(user, task_id, %{project_id: project_id}, command_id)

  defp list_visible(user, inbox) do
    Task
    |> where([t], t.user_id == ^user.id and t.inbox == ^inbox and t.state == :to_do)
    |> order_by([t], desc: t.inserted_at, desc: t.id)
    |> Repo.all()
  end
end
