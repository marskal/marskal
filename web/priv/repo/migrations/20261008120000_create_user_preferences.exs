defmodule Marskal.Repo.Migrations.CreateUserPreferences do
  use Ecto.Migration

  # ADR 0023. One row per user, keyed by the user and made with them, and
  # synced like any other row. It is never discarded; discarded_at is there
  # so pulls treat it like the rest.
  def up do
    execute """
    CREATE TABLE user_preferences (
      user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      timezone text NOT NULL DEFAULT 'Europe/Copenhagen',
      week_start smallint NOT NULL DEFAULT 1
        CONSTRAINT user_preferences_week_start CHECK (week_start BETWEEN 1 AND 7),
      discarded_at timestamptz(0),
      inserted_at timestamp(0) NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
      updated_at timestamp(0) NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
    )
    """

    execute """
    CREATE FUNCTION users_create_preferences() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      INSERT INTO user_preferences (user_id) VALUES (NEW.id);
      RETURN NEW;
    END
    $$
    """

    execute """
    CREATE TRIGGER users_create_preferences
      AFTER INSERT ON users
      FOR EACH ROW EXECUTE FUNCTION users_create_preferences()
    """

    execute "INSERT INTO user_preferences (user_id, timezone) SELECT id, timezone FROM users"
    execute "ALTER TABLE users DROP COLUMN timezone"

    # ADR 0007. The ISO day a series' weeks start on, kept from the user's
    # preference when the series was made.
    execute """
    ALTER TABLE recurrence_series ADD COLUMN week_start smallint NOT NULL DEFAULT 1
      CONSTRAINT recurrence_series_week_start CHECK (week_start BETWEEN 1 AND 7)
    """
  end

  def down do
    execute "ALTER TABLE recurrence_series DROP COLUMN week_start"
    execute "ALTER TABLE users ADD COLUMN timezone text NOT NULL DEFAULT 'Europe/Copenhagen'"

    execute """
    UPDATE users SET timezone = p.timezone FROM user_preferences p WHERE p.user_id = users.id
    """

    execute "DROP TRIGGER users_create_preferences ON users"
    execute "DROP FUNCTION users_create_preferences()"
    execute "DROP TABLE user_preferences"
  end
end
