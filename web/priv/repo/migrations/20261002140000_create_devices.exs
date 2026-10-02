defmodule Marskal.Repo.Migrations.CreateDevices do
  use Ecto.Migration

  # ADR 0021: a device is one approved OAuth consent in Hydra. The web app
  # keeps the name the user gave it, and refuses tokens of a device that is
  # gone. Server-only; not synced.
  def up do
    execute """
    CREATE TABLE devices (
      id uuid PRIMARY KEY DEFAULT uuidv7(),
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name text NOT NULL,
      client_id text NOT NULL,
      consent_request_id text NOT NULL UNIQUE,
      last_used_at timestamptz(0),
      inserted_at timestamptz(0) NOT NULL
    )
    """

    execute "CREATE INDEX devices_user_id_index ON devices (user_id)"
  end

  def down do
    execute "DROP TABLE devices"
  end
end
