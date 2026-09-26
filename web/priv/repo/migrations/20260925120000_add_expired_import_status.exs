defmodule Marskal.Repo.Migrations.AddExpiredImportStatus do
  use Ecto.Migration

  def up do
    execute "ALTER TYPE import_batch_status ADD VALUE 'expired'"
  end

  # Postgres cannot drop an enum value. Expired batches become failed and the
  # value stays unused.
  def down do
    execute """
    UPDATE import_batches
    SET status = 'failed', error_message = coalesce(error_message, 'This upload expired.')
    WHERE status = 'expired'
    """
  end
end
