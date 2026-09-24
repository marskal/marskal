defmodule Marskal.Tasks do
  @moduledoc """
  Task capture and the field-patch write path.

  Every accepted action takes a command id. Replaying that id does nothing
  the second time. The change feed records the patch.
  """

  import Ecto.Query
  alias Marskal.Accounts.User
  alias Marskal.Changes.Change
  alias Marskal.Repo
  alias Marskal.Tasks.Task

  def list_inbox(%User{} = user), do: list_visible(user, true)
  def list_open(%User{} = user), do: list_visible(user, false)

  def create_task(%User{} = user, attrs, command_id) when is_map(attrs) do
    run_command(user, command_id, fn ->
      changeset = Task.create_changeset(%Task{}, user, attrs)

      case Repo.insert(changeset) do
        {:ok, task} -> {:ok, task, encode_patch(changeset)}
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

  def complete_task(%User{} = user, task_id, command_id) do
    update_task(user, task_id, command_id, &Task.state_changeset(&1, :done))
  end

  def drop_task(%User{} = user, task_id, command_id) do
    update_task(user, task_id, command_id, &Task.state_changeset(&1, :dropped))
  end

  defp list_visible(user, inbox) do
    Task
    |> where([t], t.user_id == ^user.id and t.inbox == ^inbox and t.state == :to_do)
    |> order_by([t], desc: t.inserted_at, desc: t.id)
    |> Repo.all()
  end

  defp update_task(user, task_id, command_id, fun) do
    run_command(user, command_id, fn ->
      case Repo.get_by(Task, id: task_id, user_id: user.id) do
        nil ->
          {:error, :not_found}

        task ->
          changeset = fun.(task)

          case Repo.update(changeset) do
            {:ok, task} -> {:ok, task, encode_patch(changeset)}
            {:error, changeset} -> {:error, changeset}
          end
      end
    end)
  end

  defp run_command(user, command_id, fun) do
    with :ok <- validate_command_id(command_id) do
      Repo.transaction(fn ->
        case Repo.get_by(Change, command_id: command_id) do
          %Change{} = change ->
            replay(user, change)

          nil ->
            case fun.() do
              {:ok, %Task{} = task, patch} ->
                %Change{}
                |> Change.record_changeset(%{
                  command_id: command_id,
                  entity_type: "task",
                  entity_id: task.id,
                  patch: patch
                })
                |> Repo.insert!()

                task

              {:error, reason} ->
                Repo.rollback(reason)
            end
        end
      end)
      |> case do
        {:ok, %Task{} = task} -> {:ok, task}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp replay(user, %Change{entity_type: "task", entity_id: id}) do
    case Repo.get_by(Task, id: id, user_id: user.id) do
      %Task{} = task -> task
      nil -> Repo.rollback(:not_found)
    end
  end

  defp validate_command_id(command_id) do
    case Ecto.UUID.cast(command_id) do
      {:ok, _} -> :ok
      :error -> {:error, :invalid_command}
    end
  end

  defp encode_patch(changeset) do
    Map.new(changeset.changes, fn {key, value} ->
      {Atom.to_string(key), encode_value(value)}
    end)
  end

  defp encode_value(value) when is_boolean(value), do: value
  defp encode_value(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp encode_value(value), do: value
end
