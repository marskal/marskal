defmodule Marskal.ProjectFolders.ProjectFolder do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false, read_after_writes: true}
  @foreign_key_type Ecto.UUID

  schema "project_folders" do
    field :name, :string
    field :parent_path, {:array, :string}, default: []
    field :state, Ecto.Enum, values: [:active, :dropped], default: :active
    field :discarded_at, :utc_datetime

    belongs_to :user, Marskal.Accounts.User
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  The fields a client may write, by op (ADR 0019). Any other field rejects
  the command. A patch of `discarded_at` is a delete.
  """
  def client_fields(:insert), do: ~w(name parent_id state)
  def client_fields(:patch), do: ~w(name parent_id state discarded_at)

  def create_changeset(folder, user, attrs) do
    folder
    |> cast(attrs, [:id, :name, :parent_id, :state])
    |> validate_required([:name])
    |> validate_length(:name, max: 200)
    |> put_change(:user_id, user.id)
    |> validate_parent(user, nil)
    |> put_parent_path()
  end

  @doc """
  Any subset of name, parent_id, and state. The folder's own path changes
  only when it moves; `Marskal.ProjectFolders` refreshes descendants after a
  rename or a move.
  """
  def update_changeset(folder, user, attrs) do
    changeset =
      folder
      |> cast(attrs, [:name, :parent_id, :state])
      |> validate_required([:name, :state])
      |> validate_length(:name, max: 200)

    if changed?(changeset, :parent_id) do
      changeset
      |> validate_parent(user, folder.id)
      |> put_parent_path()
    else
      changeset
    end
  end

  def discard_changeset(folder), do: Marskal.Dates.discard(folder)

  defp validate_parent(changeset, user, self_id) do
    case get_field(changeset, :parent_id) do
      nil ->
        changeset

      parent_id when parent_id == self_id ->
        add_error(changeset, :parent_id, "would create a cycle")

      parent_id ->
        parent_changeset(changeset, user, self_id, parent_id)
    end
  end

  defp parent_changeset(changeset, user, self_id, parent_id) do
    case Marskal.Repo.get_by(__MODULE__, id: parent_id, user_id: user.id) do
      %{discarded_at: %DateTime{}} ->
        add_error(changeset, :parent_id, "must belong to you")

      nil ->
        add_error(changeset, :parent_id, "must belong to you")

      parent ->
        if cycle?(parent, self_id),
          do: add_error(changeset, :parent_id, "would create a cycle"),
          else: changeset
    end
  end

  defp cycle?(_parent, nil), do: false
  defp cycle?(nil, _self_id), do: false

  defp cycle?(parent, self_id) do
    parent.id == self_id or cycle?(parent_of(parent), self_id)
  end

  defp parent_of(%{parent_id: nil}), do: nil
  defp parent_of(%{parent_id: id}), do: Marskal.Repo.get(__MODULE__, id)

  defp put_parent_path(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp put_parent_path(changeset) do
    path =
      case get_field(changeset, :parent_id) do
        nil ->
          []

        parent_id ->
          parent = Marskal.Repo.get!(__MODULE__, parent_id)
          parent.parent_path ++ [parent.name]
      end

    put_change(changeset, :parent_path, path)
  end
end
