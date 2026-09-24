defmodule Marskal.Repo.Migrations.CreateImportBatchesAndItems do
  use Ecto.Migration

  def up do
    execute "CREATE TYPE import_batch_status AS ENUM ('pending', 'previewed', 'applying', 'applied', 'failed')"
    execute "CREATE TYPE import_channel AS ENUM ('file', 'oauth')"
    execute "CREATE TYPE import_item_kind AS ENUM ('folder', 'project', 'task')"

    execute """
    CREATE TABLE import_batches (
      id uuid PRIMARY KEY DEFAULT uuidv7(),
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      source text NOT NULL,
      channel import_channel NOT NULL DEFAULT 'file',
      status import_batch_status NOT NULL DEFAULT 'pending',
      stats jsonb NOT NULL DEFAULT '{}',
      error_message text,
      external_account text,
      filename text NOT NULL,
      payload bytea NOT NULL,
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL
    )
    """

    execute "CREATE INDEX import_batches_user_id_inserted_at_index ON import_batches (user_id, inserted_at)"

    execute """
    CREATE TABLE import_items (
      id uuid PRIMARY KEY DEFAULT uuidv7(),
      import_batch_id uuid NOT NULL REFERENCES import_batches(id) ON DELETE CASCADE,
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      source text NOT NULL,
      kind import_item_kind NOT NULL,
      source_id text NOT NULL,
      project_folder_id uuid REFERENCES project_folders(id),
      project_id uuid REFERENCES projects(id),
      task_id uuid REFERENCES tasks(id),
      extras jsonb NOT NULL DEFAULT '{}',
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL
    )
    """

    execute "CREATE UNIQUE INDEX import_items_user_source_source_id_index ON import_items (user_id, source, source_id)"

    execute "CREATE INDEX import_items_import_batch_id_kind_index ON import_items (import_batch_id, kind)"
  end

  def down do
    execute "DROP TABLE import_items"
    execute "DROP TABLE import_batches"
    execute "DROP TYPE import_item_kind"
    execute "DROP TYPE import_channel"
    execute "DROP TYPE import_batch_status"
  end
end
