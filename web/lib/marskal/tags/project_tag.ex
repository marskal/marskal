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

  @doc """
  The fields a client may write, by op (ADR 0019). Any other field rejects
  the command. `discarded_at` untags, and null tags again.
  """
  def client_fields(:insert), do: ~w(project_id tag_id)
  def client_fields(:patch), do: ~w(discarded_at)
end
