defmodule Marskal.Accounts.UserPreferences do
  @moduledoc """
  The user's preferences, one row per user, keyed by the user (ADR 0023).

  The database makes the row with the user, and it syncs like any other
  row, so a client can change a preference offline and two devices'
  changes to different preferences both land. A client only patches it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @fields [:timezone, :week_start, :locale, :home]
  @homes [:inbox, :open_tasks, :agenda, :flagged]

  # Keyed by the user. Sync names every row by `id`, so here `id` is the
  # user id too; `user_id` is the same column, for owner-scoped queries.
  @primary_key {:id, Ecto.UUID, autogenerate: false, source: :user_id}

  schema "user_preferences" do
    # Days and agendas are in this zone (ADR 0014).
    field :timezone, :string, default: "Europe/Copenhagen"
    # The ISO day weeks start on, 1 for Monday. New series take it (ADR 0007).
    field :week_start, :integer, default: 1
    # The CLDR locale dates and times are formatted in (ADR 0027).
    field :locale, :string, default: "en-150"
    # The page a login opens, when the session has no return path.
    field :home, Ecto.Enum, values: @homes, default: :open_tasks
    field :user_id, Ecto.UUID, source: :user_id

    timestamps(type: :utc_datetime)
  end

  @doc "The fields a client may write, by op (ADR 0019). The row is never inserted or deleted."
  def client_fields(:insert), do: []
  def client_fields(:patch), do: Enum.map(@fields, &Atom.to_string/1)

  def changeset(preferences, attrs) do
    preferences
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_change(:timezone, fn :timezone, zone ->
      case DateTime.now(zone) do
        {:ok, _} -> []
        {:error, _} -> [timezone: "is not a known time zone"]
      end
    end)
    |> validate_inclusion(:week_start, 1..7)
    |> validate_inclusion(:locale, Enum.map(Marskal.Cldr.known_locale_names(), &to_string/1))
    |> check_constraint(:week_start, name: :user_preferences_week_start)
    |> check_constraint(:home, name: :user_preferences_home)
  end
end
