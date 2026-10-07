defmodule Marskal.Projects do
  @moduledoc """
  Projects and the commands that change them (ADR 0009).
  """

  import Ecto.Query
  alias Marskal.Accounts.User
  alias Marskal.Changes
  alias Marskal.Projects.Project
  alias Marskal.Repo
  alias Marskal.Tasks
  alias Marskal.Tasks.Task

  def list_open(%User{} = user) do
    Project
    |> where([p], p.user_id == ^user.id and p.state == :to_do and is_nil(p.discarded_at))
    |> order_by([p], asc: p.title, asc: p.id)
    |> Repo.all()
  end

  @doc "A live project the user owns."
  def get_project(%User{} = user, id) do
    case Repo.get_owned(Project, user, id) do
      %Project{discarded_at: nil} = project -> project
      _ -> nil
    end
  end

  def create_project(%User{} = user, attrs, command_id, opts \\ []) do
    Changes.apply(user, command_id, "project", fn ->
      changeset = Project.create_changeset(%Project{}, user, attrs, opts)

      case Repo.insert(changeset) do
        {:ok, project} -> {:ok, project, changeset}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  @doc """
  Patch any of title, notes, url, project_folder_id, state, and the dates in one
  command. `at:` is as for `Marskal.Tasks.update_task/5`.
  """
  def update_project(%User{} = user, id, attrs, command_id, opts \\ []) when is_map(attrs) do
    Changes.apply(user, command_id, "project", fn ->
      case get_project(user, id) do
        nil -> {:error, :not_found}
        project -> Changes.commit(Project.update_changeset(project, attrs, opts))
      end
    end)
  end

  @doc """
  Discards the project and every task in it (ADR 0014). Each task gets its
  own change, under a command id derived from this one, so a replay
  discards nothing twice.
  """
  def delete_project(%User{} = user, id, command_id) do
    Changes.apply(user, command_id, "project", fn ->
      case get_project(user, id) do
        nil -> {:error, :not_found}
        project -> discard_project(user, command_id, project)
      end
    end)
  end

  defp discard_project(user, command_id, project) do
    project
    |> project_tasks()
    |> Enum.each(&discard_project_task(user, command_id, &1))

    changeset = Project.discard_changeset(project)
    {:ok, Repo.update!(changeset), changeset}
  end

  defp project_tasks(project) do
    Task
    |> where([t], t.project_id == ^project.id and is_nil(t.discarded_at))
    |> Repo.all()
  end

  defp discard_project_task(user, command_id, task) do
    Changes.cascade(user, command_id, "task", task.id, fn -> Tasks.discard(task) end)
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
