defmodule Marskal.Repo.Migrations.AddFlaggedToTasksAndProjects do
  use Ecto.Migration

  # ADR 0025: one flag, no priority levels.
  def change do
    for table <- [:tasks, :projects] do
      alter table(table) do
        add :flagged, :boolean, null: false, default: false
      end
    end
  end
end
