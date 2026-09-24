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

    timestamps(type: :utc_datetime)
  end

  def create_changeset(task, user, attrs) do
    task
    |> cast(attrs, [:id, :title, :notes])
    |> validate_required([:title])
    |> validate_length(:title, max: 500)
    |> validate_optional_uuid(:id)
    |> put_change(:user_id, user.id)
    |> put_change(:state, :to_do)
    |> put_change(:inbox, true)
    |> assoc_constraint(:user)
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

  defp validate_optional_uuid(changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      id ->
        case Ecto.UUID.cast(id) do
          {:ok, _} -> changeset
          :error -> add_error(changeset, field, "is invalid")
        end
    end
  end
end
