defmodule Marskal.Repo.Migrations.AddTaskOutline do
  use Ecto.Migration

  import Ecto.Query

  # ADR 0009: tasks nest under a parent task. ADR 0014: siblings are ordered
  # by a fractional rank. A child lives where its parent lives, and a task
  # is never its own ancestor.
  def up do
    execute """
    ALTER TABLE tasks
      ADD COLUMN parent_id uuid,
      ADD COLUMN rank text COLLATE "C",
      ADD CONSTRAINT tasks_parent_id_fkey
        FOREIGN KEY (parent_id, user_id) REFERENCES tasks (id, user_id)
    """

    flush()
    backfill_ranks()

    execute "ALTER TABLE tasks ALTER COLUMN rank SET NOT NULL"

    execute """
    CREATE INDEX tasks_user_id_parent_id_rank_index ON tasks (user_id, parent_id, rank)
      WHERE discarded_at IS NULL
    """

    # Checked at commit, so a subtree can move one row at a time within a
    # transaction. The rows are read again, since a later statement in the
    # transaction may have changed them.
    execute """
    CREATE FUNCTION tasks_check_outline() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE
      task tasks%ROWTYPE;
      parent tasks%ROWTYPE;
    BEGIN
      SELECT * INTO task FROM tasks WHERE id = NEW.id;

      IF task.discarded_at IS NOT NULL THEN
        IF EXISTS (
          SELECT 1 FROM tasks WHERE parent_id = task.id AND discarded_at IS NULL
        ) THEN
          RAISE EXCEPTION 'task % is discarded but has live subtasks', task.id
            USING ERRCODE = 'check_violation', CONSTRAINT = 'tasks_parent_live';
        END IF;

        RETURN NULL;
      END IF;

      IF task.parent_id IS NOT NULL THEN
        SELECT * INTO parent FROM tasks WHERE id = task.parent_id;

        IF parent.discarded_at IS NOT NULL THEN
          RAISE EXCEPTION 'task % is under discarded task %', task.id, parent.id
            USING ERRCODE = 'check_violation', CONSTRAINT = 'tasks_parent_live';
        END IF;

        IF parent.inbox IS DISTINCT FROM task.inbox
          OR parent.project_id IS DISTINCT FROM task.project_id THEN
          RAISE EXCEPTION 'task % is not where its parent % is', task.id, parent.id
            USING ERRCODE = 'check_violation', CONSTRAINT = 'tasks_parent_location';
        END IF;

        -- UNION stops at a repeated row, so this ends even on a cycle.
        IF EXISTS (
          WITH RECURSIVE up (id, parent_id) AS (
            SELECT id, parent_id FROM tasks WHERE id = task.parent_id
            UNION
            SELECT t.id, t.parent_id FROM tasks t JOIN up ON t.id = up.parent_id
          )
          SELECT 1 FROM up WHERE id = task.id
        ) THEN
          RAISE EXCEPTION 'task % would be its own ancestor', task.id
            USING ERRCODE = 'check_violation', CONSTRAINT = 'tasks_parent_cycle';
        END IF;
      END IF;

      IF EXISTS (
        SELECT 1 FROM tasks
        WHERE parent_id = task.id AND discarded_at IS NULL
          AND (inbox IS DISTINCT FROM task.inbox OR project_id IS DISTINCT FROM task.project_id)
      ) THEN
        RAISE EXCEPTION 'subtasks of task % are not where it is', task.id
          USING ERRCODE = 'check_violation', CONSTRAINT = 'tasks_parent_location';
      END IF;

      RETURN NULL;
    END
    $$
    """

    execute """
    CREATE CONSTRAINT TRIGGER tasks_outline
      AFTER INSERT OR UPDATE OF parent_id, inbox, project_id, discarded_at ON tasks
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION tasks_check_outline()
    """
  end

  def down do
    execute "DROP TRIGGER tasks_outline ON tasks"
    execute "DROP FUNCTION tasks_check_outline()"
    execute "DROP INDEX tasks_user_id_parent_id_rank_index"

    execute """
    ALTER TABLE tasks
      DROP CONSTRAINT tasks_parent_id_fkey,
      DROP COLUMN parent_id,
      DROP COLUMN rank
    """
  end

  # Every task is a root so far. Each location keeps the order its list
  # showed: the inbox newest first, projects and No project oldest first,
  # since new tasks now go to the bottom there.
  defp backfill_ranks do
    from(t in "tasks",
      select: {t.id, t.user_id, t.inbox, t.project_id, t.inserted_at},
      order_by: [asc: t.inserted_at, asc: t.id]
    )
    |> repo().all()
    |> Enum.group_by(fn {_id, user_id, inbox, project_id, _at} ->
      {user_id, inbox, project_id}
    end)
    |> Enum.each(fn {{_user, inbox, _project}, rows} ->
      ids = Enum.map(rows, &elem(&1, 0))
      ids = if inbox, do: Enum.reverse(ids), else: ids

      repo().query!(
        "UPDATE tasks SET rank = r.rank FROM unnest($1::uuid[], $2::text[]) AS r (id, rank) WHERE tasks.id = r.id",
        [ids, Marskal.Rank.spread(length(ids))]
      )
    end)
  end
end
