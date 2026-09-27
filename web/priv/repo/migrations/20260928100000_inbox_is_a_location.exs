defmodule Marskal.Repo.Migrations.InboxIsALocation do
  use Ecto.Migration

  # ADR 0017: a task sits in the inbox, in a project, or in neither. A task
  # filed while still flagged inbox counts as filed.
  def up do
    execute "UPDATE tasks SET inbox = false WHERE inbox AND project_id IS NOT NULL"

    execute """
    ALTER TABLE tasks ADD CONSTRAINT tasks_inbox_no_project
      CHECK (NOT inbox OR project_id IS NULL)
    """
  end

  def down do
    execute "ALTER TABLE tasks DROP CONSTRAINT tasks_inbox_no_project"
  end
end
