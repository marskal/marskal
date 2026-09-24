defmodule Marskal.Repo.Migrations.ScopeChangesAndOwnerKeys do
  use Ecto.Migration

  def up do
    # The change feed is pulled per user, so each row names its owner.
    execute "ALTER TABLE changes ADD COLUMN user_id uuid REFERENCES users(id) ON DELETE CASCADE"

    execute """
    UPDATE changes c SET user_id = e.user_id
    FROM (
      SELECT id, user_id, 'task' AS entity_type FROM tasks
      UNION ALL SELECT id, user_id, 'project' FROM projects
      UNION ALL SELECT id, user_id, 'project_folder' FROM project_folders
    ) e
    WHERE e.id = c.entity_id AND e.entity_type = c.entity_type
    """

    execute "DELETE FROM changes WHERE user_id IS NULL"
    execute "ALTER TABLE changes ALTER COLUMN user_id SET NOT NULL"
    execute "CREATE INDEX changes_user_id_id_index ON changes (user_id, id)"

    # A reference between user-owned rows must stay inside one owner. The
    # composite keys keep the old constraint names, which the changesets map
    # to field errors.
    execute "ALTER TABLE projects ADD CONSTRAINT projects_id_user_id_key UNIQUE (id, user_id)"

    execute "ALTER TABLE project_folders ADD CONSTRAINT project_folders_id_user_id_key UNIQUE (id, user_id)"

    execute "ALTER TABLE tasks DROP CONSTRAINT tasks_project_id_fkey"

    execute """
    ALTER TABLE tasks ADD CONSTRAINT tasks_project_id_fkey
      FOREIGN KEY (project_id, user_id) REFERENCES projects (id, user_id)
    """

    execute "ALTER TABLE projects DROP CONSTRAINT projects_project_folder_id_fkey"

    execute """
    ALTER TABLE projects ADD CONSTRAINT projects_project_folder_id_fkey
      FOREIGN KEY (project_folder_id, user_id) REFERENCES project_folders (id, user_id)
    """

    execute "ALTER TABLE project_folders DROP CONSTRAINT project_folders_parent_id_fkey"

    execute """
    ALTER TABLE project_folders ADD CONSTRAINT project_folders_parent_id_fkey
      FOREIGN KEY (parent_id, user_id) REFERENCES project_folders (id, user_id)
    """

    # The uploaded backup is dropped once the batch is applied or has failed.
    execute "ALTER TABLE import_batches ALTER COLUMN payload DROP NOT NULL"
  end

  def down do
    execute "UPDATE import_batches SET payload = ''::bytea WHERE payload IS NULL"
    execute "ALTER TABLE import_batches ALTER COLUMN payload SET NOT NULL"

    execute "ALTER TABLE project_folders DROP CONSTRAINT project_folders_parent_id_fkey"

    execute """
    ALTER TABLE project_folders ADD CONSTRAINT project_folders_parent_id_fkey
      FOREIGN KEY (parent_id) REFERENCES project_folders (id)
    """

    execute "ALTER TABLE projects DROP CONSTRAINT projects_project_folder_id_fkey"

    execute """
    ALTER TABLE projects ADD CONSTRAINT projects_project_folder_id_fkey
      FOREIGN KEY (project_folder_id) REFERENCES project_folders (id)
    """

    execute "ALTER TABLE tasks DROP CONSTRAINT tasks_project_id_fkey"

    execute """
    ALTER TABLE tasks ADD CONSTRAINT tasks_project_id_fkey
      FOREIGN KEY (project_id) REFERENCES projects (id)
    """

    execute "ALTER TABLE project_folders DROP CONSTRAINT project_folders_id_user_id_key"
    execute "ALTER TABLE projects DROP CONSTRAINT projects_id_user_id_key"

    execute "DROP INDEX changes_user_id_id_index"
    execute "ALTER TABLE changes DROP COLUMN user_id"
  end
end
