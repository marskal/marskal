defmodule Marskal.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset
  alias Marskal.Dates

  @states [:to_do, :done, :dropped]
  @title_max 500
  @notes_max 32_768

  @primary_key {:id, Ecto.UUID, autogenerate: false, read_after_writes: true}
  @foreign_key_type Ecto.UUID

  schema "tasks" do
    field :title, :string
    field :notes, :string
    field :url, :string
    field :state, Ecto.Enum, values: @states, default: :to_do
    field :inbox, :boolean, default: true
    field :defer_until, :utc_datetime
    field :deferred_indefinitely, :boolean, default: false
    field :planned_at, :utc_datetime
    field :due_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :discarded_at, :utc_datetime
    field :rank, :string
    field :occurrence_for, :utc_datetime

    belongs_to :user, Marskal.Accounts.User
    belongs_to :project, Marskal.Projects.Project
    belongs_to :parent, __MODULE__
    belongs_to :series, Marskal.Recurrence.Series

    timestamps(type: :utc_datetime)
  end

  @doc """
  The fields a client may write, by op (ADR 0019). Any other field rejects
  the command. A patch of `discarded_at` is a delete.
  """
  def client_fields(:insert),
    do:
      ~w(title notes url project_id parent_id rank inbox state defer_until deferred_indefinitely planned_at due_at series_id occurrence_for)

  def client_fields(:patch),
    do:
      ~w(title notes url project_id parent_id rank inbox state defer_until deferred_indefinitely planned_at due_at series_id occurrence_for discarded_at)

  def title_max, do: @title_max

  def notes_max, do: @notes_max

  @doc """
  A new task. `state` and `resolved_at` may be given so an import can create
  a resolved task, with its source's resolve time, in one command. A client
  may give its own `rank`; `Marskal.Tasks` places the task when it does
  not, and moves a subtask to where its parent is. `generated: true` is
  for the occurrences `Marskal.Recurrence` creates.
  """
  def create_changeset(task, user, attrs, opts \\ []) do
    task
    |> cast(attrs, [
      :id,
      :title,
      :notes,
      :url,
      :project_id,
      :parent_id,
      :rank,
      :inbox,
      :state,
      :series_id,
      :occurrence_for,
      :resolved_at | Dates.fields()
    ])
    |> validate_required([:title])
    |> validate_length(:title, max: @title_max)
    |> validate_length(:notes, max: @notes_max)
    |> Marskal.Url.validate("tasks")
    |> put_change(:user_id, user.id)
    |> default_inbox()
    |> put_location()
    |> Dates.put_defer()
    |> Dates.put_resolved_at(opts[:at])
    |> assoc_constraint(:user)
    |> owned_project_constraint()
    |> date_constraints()
    |> Marskal.Recurrence.validate_occurrence(user.id, :task, generated: opts[:generated])
    |> validate_rank()
    |> outline_constraints()
  end

  @doc """
  Any subset of the editable fields. Only fields that differ reach the
  patch. `series_id` and `occurrence_for` join a series, once.
  """
  def update_changeset(task, attrs, opts \\ []) do
    task
    |> cast(attrs, [
      :title,
      :notes,
      :url,
      :project_id,
      :inbox,
      :state,
      :series_id,
      :occurrence_for | Dates.fields()
    ])
    |> validate_required([:title, :inbox, :state])
    |> validate_length(:title, max: @title_max)
    |> validate_length(:notes, max: @notes_max)
    |> Marskal.Url.validate("tasks")
    |> put_location()
    |> Dates.put_defer()
    |> Dates.put_resolved_at(opts[:at])
    |> owned_project_constraint()
    |> date_constraints()
    |> Marskal.Recurrence.validate_occurrence(task.user_id, :task)
  end

  @doc """
  A place in the outline: `parent_id` and `rank`, with the location that
  goes with the parent. `Marskal.Tasks` works these out.
  """
  def place_changeset(task, %{parent_id: _, rank: _, inbox: _, project_id: _} = place) do
    task
    |> change(place)
    |> validate_rank()
    |> owned_project_constraint()
    |> outline_constraints()
  end

  @doc "The location a subtask takes from its parent, when the parent moves."
  def relocate_changeset(task, inbox, project_id),
    do: change(task, inbox: inbox, project_id: project_id)

  def discard_changeset(task), do: Dates.discard(task)

  defp validate_rank(changeset) do
    validate_change(changeset, :rank, fn :rank, rank ->
      if Marskal.Rank.valid?(rank), do: [], else: [rank: "is not a valid rank"]
    end)
  end

  # tasks_parent_id_fkey is (parent_id, user_id), so another user's task
  # fails here.
  defp outline_constraints(changeset) do
    foreign_key_constraint(changeset, :parent_id,
      name: :tasks_parent_id_fkey,
      message: "must be one of your tasks"
    )
  end

  defp date_constraints(changeset) do
    changeset
    |> check_constraint(:defer_until,
      name: :tasks_defer_one_shape,
      message: "cannot be set when deferred indefinitely"
    )
    |> check_constraint(:resolved_at, name: :tasks_resolved_at_set, message: "is required")
  end

  # A new task goes to the inbox unless it is given a project. A blank inbox
  # value from a form means that default, not NULL.
  defp default_inbox(changeset) do
    case fetch_change(changeset, :inbox) do
      {:ok, inbox} when is_boolean(inbox) ->
        changeset

      _ ->
        put_change(changeset, :inbox, is_nil(get_field(changeset, :project_id)))
    end
  end

  # Inbox and project are one location (ADR 0017): the inbox, a project, or
  # neither. Choosing a project leaves the inbox; choosing the inbox leaves
  # the project. A move patches both fields, so two offline moves merge as
  # one field and never pair a project with the inbox.
  defp put_location(changeset) do
    inbox = fetch_change(changeset, :inbox)
    project = fetch_change(changeset, :project_id)

    cond do
      inbox == :error and project == :error ->
        changeset

      match?({:ok, id} when is_binary(id), project) and inbox_requested?(changeset) ->
        add_error(changeset, :inbox, "cannot hold a task that has a project")

      match?({:ok, id} when is_binary(id), project) ->
        move(changeset, false, get_field(changeset, :project_id))

      inbox == {:ok, true} ->
        move(changeset, true, nil)

      true ->
        move(changeset, get_field(changeset, :inbox), get_field(changeset, :project_id))
    end
    |> check_constraint(:inbox,
      name: :tasks_inbox_no_project,
      message: "cannot hold a task that has a project"
    )
  end

  # Asked for, even if the task is already there, so the change drops it.
  defp inbox_requested?(changeset),
    do: Map.get(changeset.params, "inbox") in [true, "true"]

  defp move(changeset, inbox, project_id) do
    changeset
    |> force_change(:inbox, inbox)
    |> force_change(:project_id, project_id)
  end

  # tasks_project_id_fkey is (project_id, user_id), so another user's project
  # fails here.
  defp owned_project_constraint(changeset) do
    foreign_key_constraint(changeset, :project_id,
      name: :tasks_project_id_fkey,
      message: "must belong to you"
    )
  end
end
