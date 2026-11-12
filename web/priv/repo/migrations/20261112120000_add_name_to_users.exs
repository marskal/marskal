defmodule Marskal.Repo.Migrations.AddNameToUsers do
  use Ecto.Migration

  # What to call the user. Optional; null when they gave none. The app
  # trims it and stores an empty one as null.
  def change do
    execute(
      """
      ALTER TABLE users
        ADD COLUMN name text
          CONSTRAINT users_name CHECK (name <> '' AND char_length(name) <= 100)
      """,
      "ALTER TABLE users DROP COLUMN name"
    )
  end
end
