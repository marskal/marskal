defmodule Marskal.Changes.Change do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: false, read_after_writes: true}
  @foreign_key_type Ecto.UUID

  schema "changes" do
    field :command_id, Ecto.UUID
    field :entity_type, :string
    field :entity_id, Ecto.UUID
    field :patch, :map
    field :inserted_at, :utc_datetime

    belongs_to :user, Marskal.Accounts.User
  end

  def record_changeset(change, attrs) do
    change
    |> cast(attrs, [:command_id, :user_id, :entity_type, :entity_id, :patch])
    |> validate_required([:command_id, :user_id, :entity_type, :entity_id, :patch])
    |> put_change(:inserted_at, DateTime.utc_now(:second))
    |> unique_constraint(:command_id)
  end
end
