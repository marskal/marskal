defmodule Marskal.Repo.Migrations.CreateTasksAndChanges do
  use Ecto.Migration

  def up do
    execute "CREATE TYPE task_state AS ENUM ('to_do', 'done', 'dropped')"

    execute """
    CREATE TABLE tasks (
      id uuid PRIMARY KEY DEFAULT uuidv7(),
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      title text NOT NULL,
      notes text,
      state task_state NOT NULL DEFAULT 'to_do',
      inbox boolean NOT NULL DEFAULT true,
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL
    )
    """

    execute "CREATE INDEX tasks_user_id_inbox_state_index ON tasks (user_id, inbox, state)"

    execute """
    CREATE TABLE changes (
      id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      command_id uuid NOT NULL,
      entity_type text NOT NULL,
      entity_id uuid NOT NULL,
      patch jsonb NOT NULL,
      inserted_at timestamp(0) NOT NULL
    )
    """

    execute "CREATE UNIQUE INDEX changes_command_id_index ON changes (command_id)"
  end

  def down do
    execute "DROP TABLE changes"
    execute "DROP TABLE tasks"
    execute "DROP TYPE task_state"
  end
end
