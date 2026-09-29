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

    belongs_to :user, Marskal.Accounts.User
    belongs_to :project_folder, Marskal.ProjectFolders.ProjectFolder

    timestamps(type: :utc_datetime)
  end

  def create_changeset(project, user, attrs) do
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
    |> Dates.put_resolved_at()
    |> owned_folder_constraint()
    |> date_constraints()
  end

  @doc "Any subset of the editable fields. Only fields that differ reach the patch."
  def update_changeset(project, attrs) do
    project
    |> cast(attrs, [:title, :notes, :project_folder_id, :state | Dates.fields()])
    |> validate_required([:title, :state])
    |> validate_length(:title, max: Marskal.Tasks.Task.title_max())
    |> Dates.put_defer()
    |> Dates.put_resolved_at()
    |> owned_folder_constraint()
    |> date_constraints()
  end

  def discard_changeset(project), do: Dates.discard(project)

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
