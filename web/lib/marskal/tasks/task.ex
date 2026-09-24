defmodule Marskal.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @states [:to_do, :done, :dropped]

  @primary_key {:id, Ecto.UUID, autogenerate: false, read_after_writes: true}
  @foreign_key_type Ecto.UUID

  schema "tasks" do
    field :title, :string
    field :notes, :string
    field :state, Ecto.Enum, values: @states, default: :to_do
    field :inbox, :boolean, default: true

    belongs_to :user, Marskal.Accounts.User
    belongs_to :project, Marskal.Projects.Project

    timestamps(type: :utc_datetime)
  end

  def create_changeset(task, user, attrs) do
    inbox =
      cond do
        Map.has_key?(attrs, "inbox") -> truthy?(attrs["inbox"], true)
        Map.has_key?(attrs, :inbox) -> truthy?(attrs[:inbox], true)
        true -> true
      end

    task
    |> cast(attrs, [:id, :title, :notes, :project_id])
    |> validate_required([:title])
    |> validate_length(:title, max: 500)
    |> validate_optional_uuid(:id)
    |> put_change(:user_id, user.id)
    |> put_change(:state, :to_do)
    |> put_change(:inbox, inbox)
    |> validate_project_owner(user)
    |> assoc_constraint(:user)
    |> assoc_constraint(:project)
  end

  def notes_changeset(task, attrs) do
    cast(task, attrs, [:notes])
  end

  def file_changeset(task, user, attrs) do
    task
    |> cast(attrs, [:project_id])
    |> validate_project_owner(user)
    |> assoc_constraint(:project)
  end

  def rename_changeset(task, attrs) do
    task
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> validate_length(:title, max: 500)
  end

  def clarify_changeset(task) do
    change(task, inbox: false)
  end

  def state_changeset(task, state) when state in @states do
    change(task, state: state)
  end

  defp truthy?(value, default) when value in [nil, ""], do: default
  defp truthy?(value, _default) when value in [true, "true", "1"], do: true
  defp truthy?(value, _default) when value in [false, "false", "0"], do: false
  defp truthy?(_value, default), do: default

  defp validate_project_owner(changeset, user) do
    case get_change(changeset, :project_id) do
      nil ->
        changeset

      "" ->
        put_change(changeset, :project_id, nil)

      project_id ->
        case Marskal.Repo.get_by(Marskal.Projects.Project, id: project_id, user_id: user.id) do
          nil -> add_error(changeset, :project_id, "must belong to you")
          _project -> changeset
        end
    end
  end

  defp validate_optional_uuid(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      id ->
        case Ecto.UUID.cast(id) do
          {:ok, _} -> changeset
          :error -> add_error(changeset, field, "is invalid")
        end
    end
  end
end
