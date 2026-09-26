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

  def get_project(%User{} = user, id), do: Repo.get_owned(Project, user, id)

  def create_project(%User{} = user, attrs, command_id) do
    Changes.apply(user, command_id, "project", fn ->
      changeset = Project.create_changeset(%Project{}, user, attrs)

      case Repo.insert(changeset) do
        {:ok, project} -> {:ok, project, changeset}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  @doc "Patch any of title, notes, project_folder_id, and state in one command."
  def update_project(%User{} = user, id, attrs, command_id) when is_map(attrs) do
    Changes.apply(user, command_id, "project", fn ->
      case get_project(user, id) do
        nil ->
          {:error, :not_found}

        project ->
          changeset = Project.update_changeset(project, attrs)

          case Repo.update(changeset) do
            {:ok, project} -> {:ok, project, changeset}
            {:error, changeset} -> {:error, changeset}
          end
      end
    end)
  end

  def rename_project(user, id, title, command_id),
    do: update_project(user, id, %{title: title}, command_id)

  def set_notes(user, id, notes, command_id),
    do: update_project(user, id, %{notes: notes}, command_id)

  def file_project(user, id, folder_id, command_id),
    do: update_project(user, id, %{project_folder_id: folder_id}, command_id)

  def complete_project(user, id, command_id),
    do: update_project(user, id, %{state: :done}, command_id)

  def drop_project(user, id, command_id),
    do: update_project(user, id, %{state: :dropped}, command_id)

  def reopen_project(user, id, command_id),
    do: update_project(user, id, %{state: :to_do}, command_id)
end
