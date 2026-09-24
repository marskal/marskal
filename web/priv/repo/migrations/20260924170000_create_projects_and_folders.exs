defmodule Marskal.Repo.Migrations.CreateProjectsAndFolders do
  use Ecto.Migration

  def up do
    execute "CREATE TYPE folder_state AS ENUM ('active', 'dropped')"

    execute """
    CREATE TABLE project_folders (
      id uuid PRIMARY KEY DEFAULT uuidv7(),
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name text NOT NULL,
      parent_id uuid REFERENCES project_folders(id),
      parent_path text[] NOT NULL DEFAULT '{}',
      state folder_state NOT NULL DEFAULT 'active',
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL
    )
    """

    execute "CREATE INDEX project_folders_user_id_state_index ON project_folders (user_id, state)"
    execute "CREATE INDEX project_folders_user_id_parent_id_index ON project_folders (user_id, parent_id)"

    execute """
    CREATE TABLE projects (
      id uuid PRIMARY KEY DEFAULT uuidv7(),
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      project_folder_id uuid REFERENCES project_folders(id),
      title text NOT NULL,
      notes text,
      state task_state NOT NULL DEFAULT 'to_do',
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL
    )
    """

    execute "CREATE INDEX projects_user_id_state_index ON projects (user_id, state)"
    execute "CREATE INDEX projects_user_id_project_folder_id_index ON projects (user_id, project_folder_id)"

    execute "ALTER TABLE tasks ADD COLUMN project_id uuid REFERENCES projects(id)"
    execute "CREATE INDEX tasks_user_id_project_id_index ON tasks (user_id, project_id)"
  end

  def down do
    execute "DROP INDEX tasks_user_id_project_id_index"
    execute "ALTER TABLE tasks DROP COLUMN project_id"
    execute "DROP TABLE projects"
    execute "DROP TABLE project_folders"
    execute "DROP TYPE folder_state"
  end
end
