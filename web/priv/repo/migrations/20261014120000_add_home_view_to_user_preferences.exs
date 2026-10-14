defmodule Marskal.Repo.Migrations.AddHomeViewToUserPreferences do
  use Ecto.Migration

  # ADR 0023. The view a login opens. Existing rows open the open tasks.
  def up do
    execute """
    ALTER TABLE user_preferences
      ADD COLUMN home_view text NOT NULL DEFAULT 'open_tasks'
      CONSTRAINT user_preferences_home_view
        CHECK (home_view IN ('inbox', 'open_tasks', 'agenda', 'flagged'))
    """
  end

  def down do
    execute "ALTER TABLE user_preferences DROP COLUMN home_view"
  end
end
