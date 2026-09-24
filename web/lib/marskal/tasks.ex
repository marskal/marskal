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
  def list_open(%User{} = user), do: list_visible(user, false)

  def list_project_tasks(%User{} = user, project_id) do
    Task
    |> where(
      [t],
      t.user_id == ^user.id and t.project_id == ^project_id and t.inbox == false and
        t.state == :to_do
    )
    |> order_by([t], desc: t.inserted_at, desc: t.id)
    |> Repo.all()
  end

  def get_task(%User{} = user, id), do: Repo.get_by(Task, id: id, user_id: user.id)

  def create_task(%User{} = user, attrs, command_id) when is_map(attrs) do
    Changes.apply(user, command_id, "task", fn ->
      changeset = Task.create_changeset(%Task{}, user, attrs)

      case Repo.insert(changeset) do
        {:ok, task} -> {:ok, task, changeset}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  def rename_task(%User{} = user, task_id, title, command_id) do
    update_task(user, task_id, command_id, &Task.rename_changeset(&1, %{title: title}))
  end

  def clarify_task(%User{} = user, task_id, command_id) do
    update_task(user, task_id, command_id, &Task.clarify_changeset/1)
  end

  def set_inbox(%User{} = user, task_id, inbox, command_id) when is_boolean(inbox) do
    update_task(user, task_id, command_id, &Task.inbox_changeset(&1, inbox))
  end

  def complete_task(%User{} = user, task_id, command_id) do
    update_task(user, task_id, command_id, &Task.state_changeset(&1, :done))
  end

  def drop_task(%User{} = user, task_id, command_id) do
    update_task(user, task_id, command_id, &Task.state_changeset(&1, :dropped))
  end

  def reopen_task(%User{} = user, task_id, command_id) do
    update_task(user, task_id, command_id, &Task.state_changeset(&1, :to_do))
  end

  def set_notes(%User{} = user, task_id, notes, command_id) do
    update_task(user, task_id, command_id, &Task.notes_changeset(&1, %{notes: notes}))
  end

  def file_task(%User{} = user, task_id, project_id, command_id) do
    update_task(user, task_id, command_id, fn task ->
      Task.file_changeset(task, user, %{project_id: project_id})
    end)
  end

  defp list_visible(user, inbox) do
    Task
    |> where([t], t.user_id == ^user.id and t.inbox == ^inbox and t.state == :to_do)
    |> order_by([t], desc: t.inserted_at, desc: t.id)
    |> Repo.all()
  end

  defp update_task(user, task_id, command_id, fun) do
    Changes.apply(user, command_id, "task", fn ->
      case Repo.get_by(Task, id: task_id, user_id: user.id) do
        nil ->
          {:error, :not_found}

        task ->
          changeset = fun.(task)

          case Repo.update(changeset) do
            {:ok, task} -> {:ok, task, changeset}
            {:error, changeset} -> {:error, changeset}
          end
      end
    end)
  end
end
