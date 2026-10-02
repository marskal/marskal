defmodule Marskal.Devices.Device do
  @moduledoc "A program signed in as a user through Hydra (ADR 0021)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false, read_after_writes: true}
  @foreign_key_type Ecto.UUID

  @name_max 100

  schema "devices" do
    field :name, :string
    field :client_id, :string
    field :consent_request_id, :string
    field :last_used_at, :utc_datetime

    belongs_to :user, Marskal.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def create_changeset(device, user, attrs) do
    device
    |> cast(attrs, [:name, :client_id, :consent_request_id])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :client_id, :consent_request_id])
    |> validate_length(:name, max: @name_max)
    |> put_change(:user_id, user.id)
    |> unique_constraint(:consent_request_id)
  end
end
