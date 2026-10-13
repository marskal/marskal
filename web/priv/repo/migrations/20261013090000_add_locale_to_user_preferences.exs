defmodule Marskal.Repo.Migrations.AddLocaleToUserPreferences do
  use Ecto.Migration

  # ADR 0027. The CLDR locale dates and times are formatted in. Which names
  # are known is Marskal.Cldr's list, checked in the changeset.
  def change do
    alter table(:user_preferences) do
      add :locale, :text, null: false, default: "en-150"
    end
  end
end
