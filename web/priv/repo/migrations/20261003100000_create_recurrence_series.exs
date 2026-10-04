defmodule Marskal.Repo.Migrations.CreateRecurrenceSeries do
  use Ecto.Migration

  # ADR 0007. A series holds the rule; its occurrences are tasks or projects
  # that carry series_id and the slot the rule gave them in occurrence_for.
  def up do
    execute "CREATE TYPE recurrence_kind AS ENUM ('task', 'project')"
    execute "CREATE TYPE recurrence_mode AS ENUM ('regular', 'on_completion')"
    execute "CREATE TYPE recurrence_anchor AS ENUM ('defer', 'planned', 'due')"

    execute """
    CREATE TYPE recurrence_frequency AS ENUM
      ('minutes', 'hours', 'days', 'weeks', 'months', 'years')
    """

    execute """
    CREATE TYPE recurrence_day_kind AS ENUM
      ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
       'work_day', 'weekend_day')
    """

    # weekdays are ISO numbers, 1 for Monday. month_days are 1-31, and -1
    # for the last day. month_ordinal is 1-5, and -1 for the last.
    execute """
    CREATE TABLE recurrence_series (
      id uuid PRIMARY KEY DEFAULT uuidv7(),
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      kind recurrence_kind NOT NULL,
      mode recurrence_mode NOT NULL,
      anchor recurrence_anchor NOT NULL,
      "interval" integer NOT NULL CHECK ("interval" > 0),
      frequency recurrence_frequency NOT NULL,
      weekdays smallint[] NOT NULL DEFAULT '{}',
      month_days smallint[] NOT NULL DEFAULT '{}',
      month_ordinal smallint,
      month_day_kind recurrence_day_kind,
      ends_at timestamptz(0),
      end_count integer CHECK (end_count > 0),
      stopped_at timestamptz(0),
      discarded_at timestamptz(0),
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL,
      CONSTRAINT recurrence_series_id_user_id_kind_key UNIQUE (id, user_id, kind),
      CONSTRAINT recurrence_series_weekdays
        CHECK (weekdays <@ '{1,2,3,4,5,6,7}' AND (frequency = 'weeks' OR weekdays = '{}')),
      CONSTRAINT recurrence_series_month_days
        CHECK (
          month_days <@ '{-1,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31}'
          AND (frequency = 'months' OR month_days = '{}')
        ),
      CONSTRAINT recurrence_series_month_weekday
        CHECK (
          (month_ordinal IS NULL) = (month_day_kind IS NULL)
          AND (month_ordinal IS NULL OR frequency = 'months')
          AND (month_ordinal IS NULL OR month_ordinal IN (-1, 1, 2, 3, 4, 5))
        )
    )
    """

    for {table, kind} <- [{"tasks", "task"}, {"projects", "project"}] do
      # series_kind is a constant, so the foreign key also checks that a
      # task's series repeats tasks and a project's repeats projects.
      execute """
      ALTER TABLE #{table}
        ADD COLUMN series_id uuid,
        ADD COLUMN occurrence_for timestamptz(0),
        ADD COLUMN series_kind recurrence_kind
          GENERATED ALWAYS AS ('#{kind}'::recurrence_kind) STORED,
        ADD CONSTRAINT #{table}_series_id_fkey
          FOREIGN KEY (series_id, user_id, series_kind)
          REFERENCES recurrence_series (id, user_id, kind),
        ADD CONSTRAINT #{table}_occurrence_shape
          CHECK ((series_id IS NULL) = (occurrence_for IS NULL)),
        ADD CONSTRAINT #{table}_series_id_occurrence_for_key
          UNIQUE (series_id, occurrence_for)
      """

      # A row joins a series once, and its slot never changes (ADR 0007).
      execute """
      CREATE FUNCTION #{table}_keep_occurrence() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF OLD.series_id IS NOT NULL AND (
          NEW.series_id IS DISTINCT FROM OLD.series_id
          OR NEW.occurrence_for IS DISTINCT FROM OLD.occurrence_for
        ) THEN
          RAISE EXCEPTION '% is already occurrence % of series %',
            OLD.id, OLD.occurrence_for, OLD.series_id
            USING ERRCODE = 'check_violation', CONSTRAINT = '#{table}_occurrence_fixed';
        END IF;

        RETURN NEW;
      END
      $$
      """

      execute """
      CREATE TRIGGER #{table}_keep_occurrence
        BEFORE UPDATE OF series_id, occurrence_for ON #{table}
        FOR EACH ROW EXECUTE FUNCTION #{table}_keep_occurrence()
      """
    end
  end

  def down do
    for table <- ["tasks", "projects"] do
      execute "DROP TRIGGER #{table}_keep_occurrence ON #{table}"
      execute "DROP FUNCTION #{table}_keep_occurrence()"

      execute """
      ALTER TABLE #{table}
        DROP COLUMN series_id,
        DROP COLUMN occurrence_for,
        DROP COLUMN series_kind
      """
    end

    execute "DROP TABLE recurrence_series"
    execute "DROP TYPE recurrence_day_kind"
    execute "DROP TYPE recurrence_frequency"
    execute "DROP TYPE recurrence_anchor"
    execute "DROP TYPE recurrence_mode"
    execute "DROP TYPE recurrence_kind"
  end
end
