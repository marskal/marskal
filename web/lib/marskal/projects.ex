defmodule Marskal.Projects do
  import Ecto.Query
  alias Marskal.Accounts.User
  alias Marskal.Changes
  alias Marskal.Projects.Project
  alias Marskal.Repo

  def list_open(%User{} = user) do
    Project
    |> where([p], p.user_id == ^user.id and p.state == :to_do)
    |> order_by([p], asc: p.title, asc: p.id)
    |> Repo.all()
  end

  def get_project(%User{} = user, id), do: Repo.get_by(Project, id: id, user_id: user.id)

  def create_project(%User{} = user, attrs, command_id) do
    Changes.apply(user, command_id, "project", fn ->
      changeset = Project.create_changeset(%Project{}, user, attrs)

      case Repo.insert(changeset) do
        {:ok, project} -> {:ok, project, changeset}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  def rename_project(%User{} = user, id, title, command_id) do
    update_project(user, id, command_id, &Project.rename_changeset(&1, %{title: title}))
  end

  def set_notes(%User{} = user, id, notes, command_id) do
    update_project(user, id, command_id, &Project.notes_changeset(&1, %{notes: notes}))
  end

  def complete_project(%User{} = user, id, command_id) do
    update_project(user, id, command_id, &Project.state_changeset(&1, :done))
  end

  def drop_project(%User{} = user, id, command_id) do
    update_project(user, id, command_id, &Project.state_changeset(&1, :dropped))
  end

  def reopen_project(%User{} = user, id, command_id) do
    update_project(user, id, command_id, &Project.state_changeset(&1, :to_do))
  end

  defp update_project(user, id, command_id, fun) do
    Changes.apply(user, command_id, "project", fn ->
      case get_project(user, id) do
        nil ->
          {:error, :not_found}

        project ->
          changeset = fun.(project)

          case Repo.update(changeset) do
            {:ok, project} -> {:ok, project, changeset}
            {:error, changeset} -> {:error, changeset}
          end
      end
    end)
  end
end
