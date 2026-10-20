defmodule Marskal.Repo.Migrations.AddRankToProjectsAndFolders do
  use Ecto.Migration

  import Ecto.Query

  # ADR 0009: the folders and projects in one folder, or at the top, are one
  # sibling list, ordered by a fractional rank as tasks and tags are
  # (ADR 0014). Both tables draw ranks from that one list.
  def up do
    execute ~s(ALTER TABLE project_folders ADD COLUMN rank text COLLATE "C")
    execute ~s(ALTER TABLE projects ADD COLUMN rank text COLLATE "C")

    flush()
    backfill_ranks()

    execute "ALTER TABLE project_folders ALTER COLUMN rank SET NOT NULL"
    execute "ALTER TABLE projects ALTER COLUMN rank SET NOT NULL"

    execute """
    CREATE INDEX project_folders_user_id_parent_id_rank_index
      ON project_folders (user_id, parent_id, rank) WHERE discarded_at IS NULL
    """

    execute """
    CREATE INDEX projects_user_id_project_folder_id_rank_index
      ON projects (user_id, project_folder_id, rank) WHERE discarded_at IS NULL
    """
  end

  def down do
    execute "DROP INDEX projects_user_id_project_folder_id_rank_index"
    execute "DROP INDEX project_folders_user_id_parent_id_rank_index"
    execute "ALTER TABLE projects DROP COLUMN rank"
    execute "ALTER TABLE project_folders DROP COLUMN rank"
  end

  # Each list keeps the order the sidebar showed: folders by name, then
  # projects by title.
  defp backfill_ranks do
    folders =
      from(f in "project_folders",
        select: {f.id, f.user_id, f.parent_id, "project_folders"},
        order_by: [asc: f.name, asc: f.id]
      )
      |> repo().all()

    projects =
      from(p in "projects",
        select: {p.id, p.user_id, p.project_folder_id, "projects"},
        order_by: [asc: p.title, asc: p.id]
      )
      |> repo().all()

    (folders ++ projects)
    |> Enum.group_by(fn {_id, user_id, parent_id, _table} -> {user_id, parent_id} end)
    |> Enum.each(fn {_list, rows} ->
      ranks = Marskal.Rank.spread(length(rows))

      rows
      |> Enum.zip(ranks)
      |> Enum.group_by(fn {{_id, _user, _parent, table}, _rank} -> table end)
      |> Enum.each(fn {table, ranked} ->
        ids = Enum.map(ranked, fn {{id, _user, _parent, _table}, _rank} -> id end)
        ranks = Enum.map(ranked, &elem(&1, 1))

        repo().query!(
          "UPDATE #{table} SET rank = r.rank FROM unnest($1::uuid[], $2::text[]) AS r (id, rank) WHERE #{table}.id = r.id",
          [ids, ranks]
        )
      end)
    end)
  end
end
