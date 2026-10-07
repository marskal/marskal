defmodule Marskal.ProjectFolders do
  @moduledoc """
  Project folders, the nested containers projects are filed in (ADR 0009).
  """

  import Ecto.Query
  alias Marskal.Accounts.User
  alias Marskal.Changes
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.Projects.Project
  alias Marskal.Repo

  def list_all(%User{} = user) do
    ProjectFolder
    |> where([f], f.user_id == ^user.id and is_nil(f.discarded_at))
    |> order_by([f], asc: f.name, asc: f.id)
    |> Repo.all()
  end

  def list_active(%User{} = user) do
    ProjectFolder
    |> where([f], f.user_id == ^user.id and f.state == :active and is_nil(f.discarded_at))
    |> order_by([f], asc: f.name, asc: f.id)
    |> Repo.all()
  end

  @doc "A live folder the user owns."
  def get_folder(%User{} = user, id) do
    case Repo.get_owned(ProjectFolder, user, id) do
      %ProjectFolder{discarded_at: nil} = folder -> folder
      _ -> nil
    end
  end

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
          folder
          |> ProjectFolder.update_changeset(user, attrs)
          |> Changes.commit(&refresh_descendants!/1)
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

  @doc """
  Discards the folder and its subfolders (ADR 0014). Their projects are not
  deleted: they are unfiled, as dropping a folder does not resolve them
  (ADR 0009). Each row gets its own change under a command id derived from
  this one.
  """
  def delete_folder(%User{} = user, id, command_id) do
    Changes.apply(user, command_id, "project_folder", fn ->
      case get_folder(user, id) do
        nil -> {:error, :not_found}
        folder -> discard_subtree(user, command_id, folder)
      end
    end)
  end

  defp discard_subtree(user, command_id, folder) do
    ProjectFolder
    |> where([f], f.parent_id == ^folder.id and is_nil(f.discarded_at))
    |> Repo.all()
    |> Enum.each(fn child ->
      Changes.cascade(user, command_id, "project_folder", child.id, fn ->
        discard_subtree(user, command_id, child)
      end)
    end)

    Project
    |> where([p], p.project_folder_id == ^folder.id and is_nil(p.discarded_at))
    |> Repo.all()
    |> Enum.each(fn project ->
      Changes.cascade(user, command_id, "project", project.id, fn ->
        changeset = Ecto.Changeset.change(project, project_folder_id: nil)
        {:ok, Repo.update!(changeset), changeset}
      end)
    end)

    changeset = ProjectFolder.discard_changeset(folder)
    {:ok, Repo.update!(changeset), changeset}
  end

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
