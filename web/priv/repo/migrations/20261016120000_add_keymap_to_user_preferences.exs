defmodule Marskal.Repo.Migrations.AddKeymapToUserPreferences do
  use Ecto.Migration

  # ADR 0031. How keyboard navigation is bound. Existing rows use the standard map.
  def up do
    execute """
    ALTER TABLE user_preferences
      ADD COLUMN keymap text NOT NULL DEFAULT 'standard'
      CONSTRAINT user_preferences_keymap
        CHECK (keymap IN ('standard', 'vim'))
    """
  end

  def down do
    execute "ALTER TABLE user_preferences DROP COLUMN keymap"
  end
end
