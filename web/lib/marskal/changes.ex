defmodule Marskal.Changes do
  @moduledoc false

  alias Marskal.Changes.Change
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.Projects.Project
  alias Marskal.Repo
  alias Marskal.Tasks.Task

  def apply(user, command_id, entity_type, fun) when is_function(fun, 0) do
    with :ok <- validate_command_id(command_id) do
      Repo.transaction(fn ->
        case Repo.get_by(Change, command_id: command_id) do
          %Change{} = change ->
            replay(user, change)

          nil ->
            case fun.() do
              {:ok, %{id: id} = entity, patch} ->
                %Change{}
                |> Change.record_changeset(%{
                  command_id: command_id,
                  entity_type: entity_type,
                  entity_id: id,
                  patch: encode_patch(patch)
                })
                |> Repo.insert!()

                entity

              {:error, reason} ->
                Repo.rollback(reason)
            end
        end
      end)
      |> case do
        {:ok, entity} -> {:ok, entity}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def encode_patch(%Ecto.Changeset{} = changeset) do
    Map.new(changeset.changes, fn {key, value} ->
      {Atom.to_string(key), encode_value(value)}
    end)
  end

  defp replay(user, %Change{entity_type: type, entity_id: id}) do
    case fetch(user, type, id) do
      nil -> Repo.rollback(:not_found)
      entity -> entity
    end
  end

  defp fetch(user, "task", id), do: Repo.get_by(Task, id: id, user_id: user.id)
  defp fetch(user, "project", id), do: Repo.get_by(Project, id: id, user_id: user.id)
  defp fetch(user, "project_folder", id), do: Repo.get_by(ProjectFolder, id: id, user_id: user.id)
  defp fetch(_user, _type, _id), do: nil

  defp validate_command_id(command_id) do
    case Ecto.UUID.cast(command_id) do
      {:ok, _} -> :ok
      :error -> {:error, :invalid_command}
    end
  end

  defp encode_value(value) when is_boolean(value), do: value
  defp encode_value(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp encode_value(value), do: value
end
