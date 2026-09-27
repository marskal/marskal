defmodule Marskal.Tags.ProjectTag do
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  @foreign_key_type Ecto.UUID

  schema "project_tags" do
    field :discarded_at, :utc_datetime

    belongs_to :user, Marskal.Accounts.User
    belongs_to :project, Marskal.Projects.Project
    belongs_to :tag, Marskal.Tags.Tag

    timestamps(type: :utc_datetime)
  end
end
