defmodule Marskal.Repo.Migrations.CreateTags do
  use Ecto.Migration

  # ADR 0005. Link rows are entities with a v5 id and their own tombstone
  # (ADR 0014), so they are not a bare join table.
  def up do
    execute "CREATE TYPE tag_state AS ENUM ('active', 'on_hold', 'dropped')"

    execute """
    CREATE TABLE tags (
      id uuid PRIMARY KEY DEFAULT uuidv7(),
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name citext NOT NULL CHECK (name <> ''),
      parent_id uuid,
      parent_path text[] NOT NULL DEFAULT '{}',
      state tag_state NOT NULL DEFAULT 'active',
      rank text COLLATE "C" NOT NULL,
      merged_into_id uuid,
      discarded_at timestamp(0),
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL,
      CONSTRAINT tags_id_user_id_key UNIQUE (id, user_id),
      CONSTRAINT tags_parent_id_fkey
        FOREIGN KEY (parent_id, user_id) REFERENCES tags (id, user_id),
      CONSTRAINT tags_merged_into_id_fkey
        FOREIGN KEY (merged_into_id, user_id) REFERENCES tags (id, user_id)
    )
    """

    # One live tag per name under a parent, ignoring case; root tags share
    # the NULL parent.
    execute """
    CREATE UNIQUE INDEX tags_user_id_parent_id_name_index
      ON tags (user_id, parent_id, name) NULLS NOT DISTINCT
      WHERE discarded_at IS NULL
    """

    execute "CREATE INDEX tags_user_id_parent_id_rank_index ON tags (user_id, parent_id, rank)"

    execute "ALTER TABLE tasks ADD CONSTRAINT tasks_id_user_id_key UNIQUE (id, user_id)"

    for {table, owner} <- [{"task_tags", "task"}, {"project_tags", "project"}] do
      execute """
      CREATE TABLE #{table} (
        id uuid PRIMARY KEY,
        user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        #{owner}_id uuid NOT NULL,
        tag_id uuid NOT NULL,
        discarded_at timestamp(0),
        inserted_at timestamp(0) NOT NULL,
        updated_at timestamp(0) NOT NULL,
        CONSTRAINT #{table}_#{owner}_id_fkey
          FOREIGN KEY (#{owner}_id, user_id) REFERENCES #{owner}s (id, user_id),
        CONSTRAINT #{table}_tag_id_fkey
          FOREIGN KEY (tag_id, user_id) REFERENCES tags (id, user_id),
        CONSTRAINT #{table}_#{owner}_id_tag_id_key UNIQUE (#{owner}_id, tag_id)
      )
      """

      execute "CREATE INDEX #{table}_tag_id_index ON #{table} (tag_id) WHERE discarded_at IS NULL"
    end

    execute "ALTER TYPE import_item_kind ADD VALUE IF NOT EXISTS 'tag'"
    execute "ALTER TABLE import_items ADD COLUMN tag_id uuid REFERENCES tags(id)"
  end

  def down do
    # Postgres cannot drop an enum value; 'tag' stays on import_item_kind.
    execute "ALTER TABLE import_items DROP COLUMN tag_id"
    execute "DROP TABLE project_tags"
    execute "DROP TABLE task_tags"
    execute "ALTER TABLE tasks DROP CONSTRAINT tasks_id_user_id_key"
    execute "DROP TABLE tags"
    execute "DROP TYPE tag_state"
  end
end
