defmodule Marskal.Repo.Migrations.AddHomeToUserPreferences do
  use Ecto.Migration

  # ADR 0023. The page a login opens. Existing rows open the open tasks.
  def up do
    execute """
    ALTER TABLE user_preferences
      ADD COLUMN home text NOT NULL DEFAULT 'open_tasks'
      CONSTRAINT user_preferences_home
        CHECK (home IN ('inbox', 'open_tasks', 'agenda', 'flagged'))
    """
  end

  def down do
    execute "ALTER TABLE user_preferences DROP COLUMN home"
  end
end
