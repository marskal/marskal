defmodule Marskal.ProjectFolders do
  import Ecto.Query
  alias Marskal.Accounts.User
  alias Marskal.Changes
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.Repo

  def list_all(%User{} = user) do
    ProjectFolder
    |> where([f], f.user_id == ^user.id)
    |> order_by([f], asc: f.name, asc: f.id)
    |> Repo.all()
  end

  def list_active(%User{} = user) do
    ProjectFolder
    |> where([f], f.user_id == ^user.id and f.state == :active)
    |> order_by([f], asc: f.name, asc: f.id)
    |> Repo.all()
  end

  def get_folder(%User{} = user, id), do: Repo.get_owned(ProjectFolder, user, id)

  def create_folder(%User{} = user, attrs, command_id) do
    Changes.apply(user, command_id, "project_folder", fn ->
      changeset = ProjectFolder.create_changeset(%ProjectFolder{}, user, attrs)

      case Repo.insert(changeset) do
        {:ok, folder} -> {:ok, folder, changeset}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  @doc "Patch any of name, parent_id, and state in one command."
  def update_folder(%User{} = user, id, attrs, command_id) when is_map(attrs) do
    Changes.apply(user, command_id, "project_folder", fn ->
      case get_folder(user, id) do
        nil ->
          {:error, :not_found}

        folder ->
          changeset = ProjectFolder.update_changeset(folder, user, attrs)

          case Repo.update(changeset) do
            {:ok, folder} ->
              if Ecto.Changeset.changed?(changeset, :name) or
                   Ecto.Changeset.changed?(changeset, :parent_id) do
                refresh_descendants!(folder)
              end

              {:ok, folder, changeset}

            {:error, changeset} ->
              {:error, changeset}
          end
      end
    end)
  end

  def rename_folder(user, id, name, command_id),
    do: update_folder(user, id, %{name: name}, command_id)

  def reparent_folder(user, id, parent_id, command_id),
    do: update_folder(user, id, %{parent_id: parent_id}, command_id)

  def drop_folder(user, id, command_id),
    do: update_folder(user, id, %{state: :dropped}, command_id)

  def activate_folder(user, id, command_id),
    do: update_folder(user, id, %{state: :active}, command_id)

  # parent_path is derived and not synced (ADR 0014), so descendants are
  # rewritten here without a change row.
  defp refresh_descendants!(%ProjectFolder{} = folder) do
    path = folder.parent_path ++ [folder.name]

    ProjectFolder
    |> where([f], f.parent_id == ^folder.id)
    |> Repo.all()
    |> Enum.each(fn child ->
      child
      |> Ecto.Changeset.change(%{parent_path: path})
      |> Repo.update!()
      |> refresh_descendants!()
    end)
  end
end
