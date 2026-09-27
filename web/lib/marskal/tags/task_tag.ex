defmodule Marskal.Tags.TaskTag do
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  @foreign_key_type Ecto.UUID

  schema "task_tags" do
    field :discarded_at, :utc_datetime

    belongs_to :user, Marskal.Accounts.User
    belongs_to :task, Marskal.Tasks.Task
    belongs_to :tag, Marskal.Tags.Tag

    timestamps(type: :utc_datetime)
  end
end
