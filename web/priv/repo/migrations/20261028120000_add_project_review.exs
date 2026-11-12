defmodule Marskal.Repo.Migrations.AddProjectReview do
  use Ecto.Migration

  # ADR 0026. A review interval has date parts only, none negative, and is
  # not zero; null is Never.
  @shape """
  date_trunc('day', %{c}) = %{c}
      AND extract(year FROM %{c}) >= 0
      AND extract(month FROM %{c}) >= 0
      AND extract(day FROM %{c}) >= 0
      AND %{c} <> interval '0'
  """

  def up do
    execute """
    ALTER TABLE user_preferences
      ADD COLUMN default_review_interval interval DEFAULT 'P1W'
      CONSTRAINT user_preferences_default_review_interval
        CHECK (#{shape("default_review_interval")})
    """

    execute """
    ALTER TABLE projects
      ADD COLUMN review_interval interval
        CONSTRAINT projects_review_interval CHECK (#{shape("review_interval")}),
      ADD COLUMN next_review_on date,
      ADD COLUMN last_reviewed_at timestamptz(0)
    """

    # Every existing project is due today on its owner's clock, so the first
    # review covers all of them.
    execute """
    UPDATE projects p
      SET review_interval = 'P1W',
          next_review_on = (now() AT TIME ZONE up.timezone)::date
      FROM user_preferences up
      WHERE up.user_id = p.user_id
    """

    execute """
    ALTER TABLE projects ADD CONSTRAINT projects_next_review_on
      CHECK ((review_interval IS NULL) = (next_review_on IS NULL))
    """

    execute """
    CREATE INDEX projects_user_id_next_review_on_index ON projects (user_id, next_review_on)
      WHERE next_review_on IS NOT NULL AND state = 'to_do' AND discarded_at IS NULL
    """
  end

  def down do
    execute "DROP INDEX projects_user_id_next_review_on_index"

    execute """
    ALTER TABLE projects
      DROP COLUMN review_interval,
      DROP COLUMN next_review_on,
      DROP COLUMN last_reviewed_at
    """

    execute "ALTER TABLE user_preferences DROP COLUMN default_review_interval"
  end

  defp shape(column), do: String.replace(@shape, "%{c}", column)
end
