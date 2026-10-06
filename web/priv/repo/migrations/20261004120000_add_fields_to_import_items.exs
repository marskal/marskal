defmodule Marskal.Repo.Migrations.AddFieldsToImportItems do
  use Ecto.Migration

  # What the source said last, per field: the base of a re-import's
  # three-way merge (ADR 0013). Items imported before this have none; the
  # import's insert in the change feed stands in for it.
  def change do
    alter table(:import_items) do
      add :fields, :map
    end
  end
end
