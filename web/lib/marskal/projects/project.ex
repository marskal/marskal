defmodule Marskal.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset
  alias Marskal.Dates

  @states [:to_do, :done, :dropped]

  @primary_key {:id, Ecto.UUID, autogenerate: false, read_after_writes: true}
  @foreign_key_type Ecto.UUID

  schema "projects" do
    field :title, :string
    field :notes, :string
    field :state, Ecto.Enum, values: @states, default: :to_do
    field :defer_until, :utc_datetime
    field :deferred_indefinitely, :boolean, default: false
    field :planned_at, :utc_datetime
    field :due_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :discarded_at, :utc_datetime
    # Read-only until projects repeat (ADR 0007).
    field :occurrence_for, :utc_datetime

    belongs_to :user, Marskal.Accounts.User
    belongs_to :project_folder, Marskal.ProjectFolders.ProjectFolder
    belongs_to :series, Marskal.Recurrence.Series

    timestamps(type: :utc_datetime)
  end

  @doc """
  The fields a client may write, by op (ADR 0019). Any other field rejects
  the command. A patch of `discarded_at` is a delete.
  """
  def client_fields(:insert),
    do:
      ~w(title notes project_folder_id state defer_until deferred_indefinitely planned_at due_at)

  def client_fields(:patch),
    do:
      ~w(title notes project_folder_id state defer_until deferred_indefinitely planned_at due_at discarded_at)

  def create_changeset(project, user, attrs, opts \\ []) do
    project
    |> cast(attrs, [
      :id,
      :title,
      :notes,
      :project_folder_id,
      :state,
      :resolved_at | Dates.fields()
    ])
    |> validate_required([:title])
    |> validate_length(:title, max: Marskal.Tasks.Task.title_max())
    |> put_change(:user_id, user.id)
    |> Dates.put_defer()
    |> Dates.put_resolved_at(opts[:at])
    |> owned_folder_constraint()
    |> validate_live_folder()
    |> date_constraints()
  end

  @doc "Any subset of the editable fields. Only fields that differ reach the patch."
  def update_changeset(project, attrs, opts \\ []) do
    project
    |> cast(attrs, [:title, :notes, :project_folder_id, :state | Dates.fields()])
    |> validate_required([:title, :state])
    |> validate_length(:title, max: Marskal.Tasks.Task.title_max())
    |> Dates.put_defer()
    |> Dates.put_resolved_at(opts[:at])
    |> owned_folder_constraint()
    |> validate_live_folder()
    |> date_constraints()
  end

  def discard_changeset(project), do: Dates.discard(project)

  # A discarded folder takes no projects. Another user's folder fails the
  # foreign key below.
  defp validate_live_folder(changeset) do
    validate_change(changeset, :project_folder_id, fn :project_folder_id, id ->
      case Marskal.Repo.get(Marskal.ProjectFolders.ProjectFolder, id) do
        %{discarded_at: %DateTime{}} -> [project_folder_id: "must belong to you"]
        _ -> []
      end
    end)
  end

  # projects_project_folder_id_fkey is (project_folder_id, user_id).
  defp owned_folder_constraint(changeset) do
    foreign_key_constraint(changeset, :project_folder_id,
      name: :projects_project_folder_id_fkey,
      message: "must belong to you"
    )
  end

  defp date_constraints(changeset) do
    changeset
    |> check_constraint(:defer_until,
      name: :projects_defer_one_shape,
      message: "cannot be set when deferred indefinitely"
    )
    |> check_constraint(:resolved_at, name: :projects_resolved_at_set, message: "is required")
  end
end
