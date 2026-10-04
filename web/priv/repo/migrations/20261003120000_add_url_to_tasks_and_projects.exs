defmodule Marskal.Repo.Migrations.AddUrlToTasksAndProjects do
  use Ecto.Migration

  # ADR 0022: one optional absolute URL. The changeset also refuses the
  # schemes that run in the page.
  def up do
    for table <- ["tasks", "projects"] do
      execute "ALTER TABLE #{table} ADD COLUMN url text"

      execute """
      ALTER TABLE #{table} ADD CONSTRAINT #{table}_url_absolute
        CHECK (url ~ '^[A-Za-z][A-Za-z0-9+.-]*:[^[:space:]]+$' AND char_length(url) <= 2048)
      """
    end
  end

  def down do
    for table <- ["tasks", "projects"] do
      execute "ALTER TABLE #{table} DROP COLUMN url"
    end
  end
end
