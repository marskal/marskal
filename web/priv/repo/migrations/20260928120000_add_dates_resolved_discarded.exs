defmodule Marskal.Repo.Migrations.AddDatesResolvedDiscarded do
  use Ecto.Migration

  # ADR 0006: Defer (until or indefinite), Planned, and Due on tasks and
  # projects. ADR 0014: resolved_at is set on the first resolve, and
  # discarded_at is the tombstone.
  def up do
    for table <- ["tasks", "projects"] do
      execute """
      ALTER TABLE #{table}
        ADD COLUMN defer_until timestamptz(0),
        ADD COLUMN deferred_indefinitely boolean NOT NULL DEFAULT false,
        ADD COLUMN planned_at timestamptz(0),
        ADD COLUMN due_at timestamptz(0),
        ADD COLUMN resolved_at timestamptz(0),
        ADD COLUMN discarded_at timestamptz(0)
      """

      execute """
      ALTER TABLE #{table} ADD CONSTRAINT #{table}_defer_one_shape
        CHECK (NOT deferred_indefinitely OR defer_until IS NULL)
      """

      # Rows resolved before this column existed get their last update.
      execute """
      UPDATE #{table} SET resolved_at = updated_at AT TIME ZONE 'UTC'
        WHERE state <> 'to_do'
      """

      # A reopened row keeps its first resolve (ADR 0014), so only the
      # resolved states are checked.
      execute """
      ALTER TABLE #{table} ADD CONSTRAINT #{table}_resolved_at_set
        CHECK (state = 'to_do' OR resolved_at IS NOT NULL)
      """
    end

    execute """
    CREATE INDEX tasks_user_id_planned_at_index ON tasks (user_id, planned_at)
      WHERE planned_at IS NOT NULL AND discarded_at IS NULL
    """
  end

  def down do
    execute "DROP INDEX tasks_user_id_planned_at_index"

    for table <- ["tasks", "projects"] do
      execute """
      ALTER TABLE #{table}
        DROP COLUMN defer_until,
        DROP COLUMN deferred_indefinitely,
        DROP COLUMN planned_at,
        DROP COLUMN due_at,
        DROP COLUMN resolved_at,
        DROP COLUMN discarded_at
      """
    end
  end
end
