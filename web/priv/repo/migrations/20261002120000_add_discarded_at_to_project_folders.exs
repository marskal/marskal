defmodule Marskal.Repo.Migrations.AddDiscardedAtToProjectFolders do
  use Ecto.Migration

  # ADR 0014: a removed folder is a tombstone the feed can carry, like tasks
  # and projects.
  def up do
    execute "ALTER TABLE project_folders ADD COLUMN discarded_at timestamptz(0)"
  end

  def down do
    execute "ALTER TABLE project_folders DROP COLUMN discarded_at"
  end
end
