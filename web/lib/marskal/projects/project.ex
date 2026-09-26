defmodule Marskal.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @states [:to_do, :done, :dropped]

  @primary_key {:id, Ecto.UUID, autogenerate: false, read_after_writes: true}
  @foreign_key_type Ecto.UUID

  schema "projects" do
    field :title, :string
    field :notes, :string
    field :state, Ecto.Enum, values: @states, default: :to_do

    belongs_to :user, Marskal.Accounts.User
    belongs_to :project_folder, Marskal.ProjectFolders.ProjectFolder

    timestamps(type: :utc_datetime)
  end

  def create_changeset(project, user, attrs) do
    project
    |> cast(attrs, [:id, :title, :notes, :project_folder_id, :state])
    |> validate_required([:title])
    |> validate_length(:title, max: Marskal.Tasks.Task.title_max())
    |> put_change(:user_id, user.id)
    |> owned_folder_constraint()
  end

  @doc "Any subset of the editable fields. Only fields that differ reach the patch."
  def update_changeset(project, attrs) do
    project
    |> cast(attrs, [:title, :notes, :project_folder_id, :state])
    |> validate_required([:title, :state])
    |> validate_length(:title, max: Marskal.Tasks.Task.title_max())
    |> owned_folder_constraint()
  end

  # projects_project_folder_id_fkey is (project_folder_id, user_id).
  defp owned_folder_constraint(changeset) do
    foreign_key_constraint(changeset, :project_folder_id,
      name: :projects_project_folder_id_fkey,
      message: "must belong to you"
    )
  end
end
