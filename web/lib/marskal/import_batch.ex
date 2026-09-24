defmodule Marskal.ImportBatch do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false, read_after_writes: true}
  @foreign_key_type Ecto.UUID

  schema "import_batches" do
    field :source, :string
    field :channel, Ecto.Enum, values: [:file, :oauth], default: :file

    field :status, Ecto.Enum,
      values: [:pending, :previewed, :applying, :applied, :failed, :expired],
      default: :pending

    field :stats, :map, default: %{}
    field :error_message, :string
    field :external_account, :string
    field :filename, :string
    # Up to 50 MB. Load it with Marskal.Imports.load_payload/1.
    field :payload, :binary, load_in_query: false

    belongs_to :user, Marskal.Accounts.User
    has_many :import_items, Marskal.ImportItem

    timestamps(type: :utc_datetime)
  end

  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [
      :user_id,
      :source,
      :channel,
      :status,
      :stats,
      :error_message,
      :external_account,
      :filename,
      :payload
    ])
    |> validate_required([:user_id, :source, :channel, :status, :filename, :payload])
    |> validate_payload_size()
  end

  defp validate_payload_size(changeset) do
    case get_change(changeset, :payload) do
      nil ->
        changeset

      payload when byte_size(payload) > 50 * 1024 * 1024 ->
        add_error(changeset, :payload, "is too large (maximum is 50 MB)")

      _ ->
        changeset
    end
  end
end
