defmodule Marskal.ProjectFolders do
  import Ecto.Query
  alias Marskal.Accounts.User
  alias Marskal.Changes
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.Repo

  def list_active(%User{} = user) do
    ProjectFolder
    |> where([f], f.user_id == ^user.id and f.state == :active)
    |> order_by([f], asc: f.name, asc: f.id)
    |> Repo.all()
  end

  def get_folder(%User{} = user, id), do: Repo.get_by(ProjectFolder, id: id, user_id: user.id)

  def create_folder(%User{} = user, attrs, command_id) do
    Changes.apply(user, command_id, "project_folder", fn ->
      changeset = ProjectFolder.create_changeset(%ProjectFolder{}, user, attrs)

      case Repo.insert(changeset) do
        {:ok, folder} -> {:ok, folder, changeset}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  def rename_folder(%User{} = user, id, name, command_id) do
    update_folder(user, id, command_id, &ProjectFolder.rename_changeset(&1, user, %{name: name}))
  end

  def reparent_folder(%User{} = user, id, parent_id, command_id) do
    update_folder(user, id, command_id, fn folder ->
      ProjectFolder.reparent_changeset(folder, user, %{parent_id: parent_id})
    end)
  end

  def drop_folder(%User{} = user, id, command_id) do
    update_folder(user, id, command_id, &ProjectFolder.state_changeset(&1, :dropped))
  end

  def activate_folder(%User{} = user, id, command_id) do
    update_folder(user, id, command_id, &ProjectFolder.state_changeset(&1, :active))
  end

  defp update_folder(user, id, command_id, fun) do
    Changes.apply(user, command_id, "project_folder", fn ->
      case get_folder(user, id) do
        nil ->
          {:error, :not_found}

        folder ->
          changeset = fun.(folder)

          case Repo.update(changeset) do
            {:ok, folder} ->
              refresh_descendants!(folder)
              {:ok, folder, changeset}

            {:error, changeset} ->
              {:error, changeset}
          end
      end
    end)
  end

  def refresh_descendants!(%ProjectFolder{} = folder) do
    children =
      ProjectFolder
      |> where([f], f.parent_id == ^folder.id)
      |> Repo.all()

    Enum.each(children, fn child ->
      path = folder.parent_path ++ [folder.name]

      child
      |> Ecto.Changeset.change(%{parent_path: path})
      |> Repo.update!()
      |> refresh_descendants!()
    end)

    folder
  end
end
