defmodule Marskal.Projects do
  @moduledoc """
  Projects and the commands that change them (ADR 0009).
  """

  import Ecto.Query
  alias Marskal.Accounts
  alias Marskal.Accounts.User
  alias Marskal.Changes
  alias Marskal.Projects.Project
  alias Marskal.Repo
  alias Marskal.ReviewInterval
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
  Patch any of title, notes, url, flagged, project_folder_id, state, the dates,
  and the review fields in one command. A new review interval without a
  next review day moves that day too (ADR 0026). `at:` is as for `Marskal.Tasks.update_task/5`. Resolving the
  latest occurrence of a series creates the next one (ADR 0007).
  """
  def update_project(%User{} = user, id, attrs, command_id, opts \\ []) when is_map(attrs) do
    Changes.apply(user, command_id, "project", fn ->
      case get_project(user, id) do
        nil -> {:error, :not_found}
        project -> commit_update(user, command_id, project, attrs, opts)
      end
    end)
  end

  defp commit_update(user, command_id, project, attrs, opts) do
    opts = put_review_zone(opts, user, attrs)

    with {:ok, updated, changeset} <-
           Changes.commit(Project.update_changeset(project, attrs, opts)) do
      if Ecto.Changeset.changed?(changeset, :state) and updated.state in [:done, :dropped] do
        Marskal.Recurrence.occurrence_resolved(user, command_id, updated)
      end

      {:ok, updated, changeset}
    end
  end

  # A new review interval counts from a day on the user's clock.
  defp put_review_zone(opts, user, attrs) do
    if Map.has_key?(attrs, :review_interval) or Map.has_key?(attrs, "review_interval"),
      do: Keyword.put_new(opts, :timezone, Accounts.timezone(user)),
      else: opts
  end

  @doc """
  Marks the project reviewed now: it is next due its interval after today
  on the user's clock (ADR 0026). A project set to Never is not reviewed.
  `at:` is the instant it was reviewed, for a command made earlier.
  """
  def mark_reviewed(%User{} = user, id, command_id, opts \\ []) do
    Changes.apply(user, command_id, "project", fn ->
      case get_project(user, id) do
        nil -> {:error, :not_found}
        %Project{review_interval: nil} -> {:error, :not_reviewed}
        project -> commit_review(user, project, opts[:at] || DateTime.utc_now())
      end
    end)
  end

  defp commit_review(user, project, at) do
    today = at |> DateTime.shift_zone!(Accounts.timezone(user)) |> DateTime.to_date()

    project
    |> Project.update_changeset(%{
      last_reviewed_at: DateTime.truncate(at, :second),
      next_review_on: ReviewInterval.next_on(today, project.review_interval)
    })
    |> Changes.commit()
  end

  @doc """
  Discards the project and every task in it (ADR 0014). Each task gets its
  own change, under a command id derived from this one, so a replay
  discards nothing twice. Deleting a series' latest occurrence ends the
  series (ADR 0007).
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

    Marskal.Recurrence.occurrence_deleted(user, command_id, project)

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
