defmodule Marskal.Repo.Migrations.OnDaysFromTheEnd do
  use Ecto.Migration

  # ADR 0007 (2026-10-09). A day row's ordinal may count from the end of
  # the month, −1 to −5: the second to last day, the 2nd to last Friday.
  # Work days go to the 23rd and weekend days to the 10th, as many as a
  # month can have.
  @wide "((-[1-5]|[1-9]|[12][0-9]|3[01]):day" <>
          "|(-[1-5]|[1-5]):(monday|tuesday|wednesday|thursday|friday|saturday|sunday)" <>
          "|(-[1-5]|[1-9]|1[0-9]|2[0-3]):work_day" <>
          "|(-[1-5]|[1-9]|10):weekend_day)"

  @narrow "((-1|[1-9]|[12][0-9]|3[01]):day" <>
            "|(-1|[1-5]):(monday|tuesday|wednesday|thursday|friday|saturday|sunday" <>
            "|work_day|weekend_day))"

  def up, do: replace_check(@wide)

  # Rows the old check does not take are dropped.
  def down do
    execute """
    UPDATE recurrence_series SET on_days = ARRAY(
      SELECT day FROM unnest(on_days) AS day
      WHERE day ~ '^(([1-9]|1[0-2]):)?#{@narrow}$'
    )
    """

    replace_check(@narrow)
  end

  defp replace_check(pattern) do
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
      FROM unnest(days) AS day, (SELECT '#{pattern}' AS pattern) AS rule
    $$
    """
  end
end
