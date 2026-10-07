defmodule Marskal.Tags.Tag do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @states [:active, :on_hold, :dropped]
  @name_max 200

  @primary_key {:id, Ecto.UUID, autogenerate: false, read_after_writes: true}
  @foreign_key_type Ecto.UUID

  schema "tags" do
    field :name, :string
    field :parent_path, {:array, :string}, default: []
    field :state, Ecto.Enum, values: @states, default: :active
    field :rank, :string
    field :discarded_at, :utc_datetime

    belongs_to :user, Marskal.Accounts.User
    belongs_to :parent, __MODULE__
    belongs_to :merged_into, __MODULE__

    timestamps(type: :utc_datetime)
  end

  @doc """
  The fields a client may write, by op (ADR 0019). Any other field rejects
  the command. A patch of `discarded_at` is a delete.
  """
  def client_fields(:insert), do: ~w(name parent_id state)
  def client_fields(:patch), do: ~w(name parent_id state discarded_at)

  def states, do: @states

  @doc "The segments from the root to this tag."
  def path(%__MODULE__{} = tag), do: tag.parent_path ++ [tag.name]

  @doc """
  A new tag. `rank_for` gives the rank after the last sibling under a
  parent id; `Marskal.Tags` supplies it.
  """
  def create_changeset(tag, user, attrs, rank_for) do
    changeset =
      tag
      |> cast(attrs, [:id, :name, :parent_id, :state])
      |> normalize_name()
      |> validate_required([:name])
      |> validate_length(:name, max: @name_max)
      |> put_change(:user_id, user.id)
      |> validate_parent(user, nil)
      |> put_parent_path()

    changeset
    |> put_rank(rank_for)
    |> unique_name()
  end

  @doc """
  Any subset of name, parent_id, and state. A move also takes a new rank at
  the end of its new siblings; `Marskal.Tags` refreshes descendants' paths.
  """
  def update_changeset(tag, user, attrs, rank_for) do
    changeset =
      tag
      |> cast(attrs, [:name, :parent_id, :state])
      |> normalize_name()
      |> validate_required([:name, :state])
      |> validate_length(:name, max: @name_max)

    changeset =
      if changed?(changeset, :parent_id) do
        changeset
        |> validate_parent(user, tag.id)
        |> put_parent_path()
        |> put_rank(rank_for)
      else
        changeset
      end

    unique_name(changeset)
  end

  @doc "Soft delete (ADR 0014). `merged_into_id` is set when folding a duplicate."
  def discard_changeset(tag, merged_into_id \\ nil) do
    change(tag,
      discarded_at: DateTime.utc_now(:second),
      merged_into_id: merged_into_id || tag.merged_into_id
    )
  end

  # Names are compared as the user sees them: trimmed and in NFC, so the
  # same letters typed two ways clash.
  defp normalize_name(changeset) do
    update_change(changeset, :name, fn
      name when is_binary(name) -> name |> String.trim() |> String.normalize(:nfc)
      name -> name
    end)
  end

  defp unique_name(changeset) do
    unique_constraint(changeset, :name,
      name: :tags_user_id_parent_id_name_index,
      message: "is already used here"
    )
  end

  defp validate_parent(%Ecto.Changeset{valid?: false} = changeset, _user, _self_id),
    do: changeset

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
    case live_parent(user, parent_id) do
      nil ->
        add_error(changeset, :parent_id, "must belong to you")

      parent ->
        if self_id && self_id in ancestor_ids(parent),
          do: add_error(changeset, :parent_id, "would create a cycle"),
          else: changeset
    end
  end

  defp live_parent(user, parent_id) do
    case Ecto.UUID.cast(parent_id) do
      {:ok, id} ->
        Marskal.Repo.one(
          from t in __MODULE__,
            where: t.id == ^id and t.user_id == ^user.id and is_nil(t.discarded_at)
        )

      :error ->
        nil
    end
  end

  defp ancestor_ids(%__MODULE__{parent_id: nil} = tag), do: [tag.id]

  defp ancestor_ids(%__MODULE__{} = tag),
    do: [tag.id | ancestor_ids(Marskal.Repo.get!(__MODULE__, tag.parent_id))]

  defp put_rank(%Ecto.Changeset{valid?: false} = changeset, _rank_for), do: changeset

  defp put_rank(changeset, rank_for),
    do: put_change(changeset, :rank, rank_for.(get_field(changeset, :parent_id)))

  defp put_parent_path(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp put_parent_path(changeset) do
    path =
      case get_field(changeset, :parent_id) do
        nil -> []
        parent_id -> path(Marskal.Repo.get!(__MODULE__, parent_id))
      end

    put_change(changeset, :parent_path, path)
  end
end
