defmodule Marskal.Repo.Migrations.SeriesOnDays do
  use Ecto.Migration

  # ADR 0007 (2026-10-09). The days a monthly or yearly rule lands on are one
  # list of rows, as the editor shows them: "14:day", "-1:day", "2:tuesday",
  # "-1:work_day" for a month, and the month first for a year, as in
  # "10:-1:monday". It replaces month_days and the single nth weekday.
  def up do
    # A CHECK cannot hold a subquery, so each row is checked in a function.
    execute """
    CREATE FUNCTION recurrence_on_days_valid(days text[], frequency recurrence_frequency)
      RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
      SELECT coalesce(bool_and(
        CASE frequency
          WHEN 'months' THEN day ~ ('^' || pattern || '$')
          WHEN 'years' THEN day ~ ('^([1-9]|1[0-2]):' || pattern || '$')
          ELSE false
        END
      ), true)
      FROM unnest(days) AS day,
        (SELECT '((-1|[1-9]|[12][0-9]|3[01]):day'
          || '|(-1|[1-5]):(monday|tuesday|wednesday|thursday|friday|saturday|sunday'
          || '|work_day|weekend_day))' AS pattern) AS rule
    $$
    """

    execute "ALTER TABLE recurrence_series ADD COLUMN on_days text[] NOT NULL DEFAULT '{}'"

    execute """
    UPDATE recurrence_series SET on_days =
      ARRAY(SELECT day::text || ':day' FROM unnest(month_days) AS day)
      || CASE
           WHEN month_ordinal IS NULL THEN '{}'::text[]
           ELSE ARRAY[month_ordinal::text || ':' || month_day_kind::text]
         END
    """

    execute """
    ALTER TABLE recurrence_series
      DROP CONSTRAINT recurrence_series_month_days,
      DROP CONSTRAINT recurrence_series_month_weekday,
      DROP COLUMN month_days,
      DROP COLUMN month_ordinal,
      DROP COLUMN month_day_kind,
      ADD CONSTRAINT recurrence_series_on_days
        CHECK (recurrence_on_days_valid(on_days, frequency))
    """

    execute "DROP TYPE recurrence_day_kind"
  end

  # A yearly row, or a second nth weekday, has no column to go back to and
  # is left out.
  def down do
    execute """
    CREATE TYPE recurrence_day_kind AS ENUM
      ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
       'work_day', 'weekend_day')
    """

    execute """
    ALTER TABLE recurrence_series
      DROP CONSTRAINT recurrence_series_on_days,
      ADD COLUMN month_days smallint[] NOT NULL DEFAULT '{}',
      ADD COLUMN month_ordinal smallint,
      ADD COLUMN month_day_kind recurrence_day_kind
    """

    execute """
    UPDATE recurrence_series SET
      month_days = ARRAY(
        SELECT split_part(day, ':', 1)::smallint FROM unnest(on_days) AS day
        WHERE day ~ '^-?[0-9]+:day$'
      ),
      month_ordinal = (
        SELECT split_part(day, ':', 1)::smallint FROM unnest(on_days) AS day
        WHERE day ~ '^-?[0-9]+:[a-z_]+$' AND day !~ ':day$' LIMIT 1
      ),
      month_day_kind = (
        SELECT split_part(day, ':', 2)::recurrence_day_kind FROM unnest(on_days) AS day
        WHERE day ~ '^-?[0-9]+:[a-z_]+$' AND day !~ ':day$' LIMIT 1
      )
    WHERE frequency = 'months'
    """

    execute """
    ALTER TABLE recurrence_series
      DROP COLUMN on_days,
      ADD CONSTRAINT recurrence_series_month_days
        CHECK (
          month_days <@ '{-1,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31}'
          AND (frequency = 'months' OR month_days = '{}')
        ),
      ADD CONSTRAINT recurrence_series_month_weekday
        CHECK (
          (month_ordinal IS NULL) = (month_day_kind IS NULL)
          AND (month_ordinal IS NULL OR frequency = 'months')
          AND (month_ordinal IS NULL OR month_ordinal IN (-1, 1, 2, 3, 4, 5))
        )
    """

    execute "DROP FUNCTION recurrence_on_days_valid(text[], recurrence_frequency)"
  end
end
