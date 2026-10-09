defmodule Marskal.Repo.Migrations.OnDaysFromTheEnd do
  use Ecto.Migration

  # ADR 0007 (2026-10-09). A day row's ordinal may count from the end of
  # the month, −1 to −5: the second to last day, the 2nd to last Friday.
  def up, do: replace_check("-[1-5]")

  # The old check takes only the last from the end; other such rows go.
  def down do
    execute """
    UPDATE recurrence_series SET on_days = ARRAY(
      SELECT day FROM unnest(on_days) AS day WHERE day !~ '(^|:)-[2-5]:'
    )
    """

    replace_check("-1")
  end

  defp replace_check(from_end) do
    execute """
    CREATE OR REPLACE FUNCTION recurrence_on_days_valid(days text[], frequency recurrence_frequency)
      RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
      SELECT coalesce(bool_and(
        CASE frequency
          WHEN 'months' THEN day ~ ('^' || pattern || '$')
          WHEN 'years' THEN day ~ ('^([1-9]|1[0-2]):' || pattern || '$')
          ELSE false
        END
      ), true)
      FROM unnest(days) AS day,
        (SELECT '((#{from_end}|[1-9]|[12][0-9]|3[01]):day'
          || '|(#{from_end}|[1-5]):(monday|tuesday|wednesday|thursday|friday|saturday|sunday'
          || '|work_day|weekend_day))' AS pattern) AS rule
    $$
    """
  end
end
