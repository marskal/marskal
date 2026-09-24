defmodule Marskal.ProjectFolders.ProjectFolder do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false, read_after_writes: true}
  @foreign_key_type Ecto.UUID

  schema "project_folders" do
    field :name, :string
    field :parent_path, {:array, :string}, default: []
    field :state, Ecto.Enum, values: [:active, :dropped], default: :active

    belongs_to :user, Marskal.Accounts.User
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  def create_changeset(folder, user, attrs) do
    folder
    |> cast(attrs, [:id, :name, :parent_id])
    |> validate_required([:name])
    |> validate_length(:name, max: 200)
    |> put_change(:user_id, user.id)
    |> put_change(:state, :active)
    |> validate_parent(user, nil)
    |> put_parent_path()
  end

  def rename_changeset(folder, user, attrs) do
    folder
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 200)
    |> put_parent_path_from(user)
  end

  def reparent_changeset(folder, user, attrs) do
    folder
    |> cast(attrs, [:parent_id])
    |> validate_parent(user, folder.id)
    |> put_parent_path()
  end

  def state_changeset(folder, state) when state in [:active, :dropped] do
    change(folder, state: state)
  end

  defp validate_parent(changeset, user, self_id) do
    parent_id = get_field(changeset, :parent_id)

    cond do
      parent_id in [nil, ""] ->
        put_change(changeset, :parent_id, nil)

      self_id && parent_id == self_id ->
        add_error(changeset, :parent_id, "would create a cycle")

      true ->
        case Marskal.Repo.get_by(__MODULE__, id: parent_id, user_id: user.id) do
          nil ->
            add_error(changeset, :parent_id, "must belong to you")

          parent ->
            if cycle?(parent, self_id),
              do: add_error(changeset, :parent_id, "would create a cycle"),
              else: changeset
        end
    end
  end

  defp cycle?(_parent, nil), do: false

  defp cycle?(parent, self_id) do
    parent.id == self_id or cycle?(parent_of(parent), self_id)
  end

  defp parent_of(%{parent_id: nil}), do: nil
  defp parent_of(%{parent_id: id}), do: Marskal.Repo.get(__MODULE__, id)

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

  defp put_parent_path_from(changeset, _user) do
    folder = changeset.data

    path =
      case folder.parent_id do
        nil ->
          []

        parent_id ->
          parent = Marskal.Repo.get!(__MODULE__, parent_id)
          parent.parent_path ++ [parent.name]
      end

    put_change(changeset, :parent_path, path)
  end
end
