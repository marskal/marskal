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
    |> cast(attrs, [:id, :title, :notes, :project_folder_id])
    |> validate_required([:title])
    |> validate_length(:title, max: 200)
    |> put_change(:user_id, user.id)
    |> put_change(:state, :to_do)
    |> validate_folder(user)
    |> assoc_constraint(:project_folder)
  end

  def rename_changeset(project, attrs) do
    project
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> validate_length(:title, max: 200)
  end

  def notes_changeset(project, attrs) do
    cast(project, attrs, [:notes])
  end

  def file_changeset(project, user, attrs) do
    project
    |> cast(attrs, [:project_folder_id])
    |> validate_folder(user)
    |> assoc_constraint(:project_folder)
  end

  def state_changeset(project, state) when state in @states do
    change(project, state: state)
  end

  defp validate_folder(changeset, user) do
    case get_change(changeset, :project_folder_id) do
      nil ->
        changeset

      "" ->
        put_change(changeset, :project_folder_id, nil)

      folder_id ->
        case Marskal.Repo.get_by(Marskal.ProjectFolders.ProjectFolder,
               id: folder_id,
               user_id: user.id
             ) do
          nil -> add_error(changeset, :project_folder_id, "must belong to you")
          _folder -> changeset
        end
    end
  end
end
