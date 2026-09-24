defmodule Marskal.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @states [:to_do, :done, :dropped]
  @title_max 500

  @primary_key {:id, Ecto.UUID, autogenerate: false, read_after_writes: true}
  @foreign_key_type Ecto.UUID

  schema "tasks" do
    field :title, :string
    field :notes, :string
    field :state, Ecto.Enum, values: @states, default: :to_do
    field :inbox, :boolean, default: true

    belongs_to :user, Marskal.Accounts.User
    belongs_to :project, Marskal.Projects.Project

    timestamps(type: :utc_datetime)
  end

  def title_max, do: @title_max

  @doc """
  A new task. `state` may be given so an import can create a resolved task
  in one command.
  """
  def create_changeset(task, user, attrs) do
    task
    |> cast(attrs, [:id, :title, :notes, :project_id, :inbox, :state])
    |> validate_required([:title])
    |> validate_length(:title, max: @title_max)
    |> put_change(:user_id, user.id)
    |> default_inbox()
    |> assoc_constraint(:user)
    |> owned_project_constraint()
  end

  @doc "Any subset of the editable fields. Only fields that differ reach the patch."
  def update_changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :notes, :project_id, :inbox, :state])
    |> validate_required([:title, :inbox, :state])
    |> validate_length(:title, max: @title_max)
    |> owned_project_constraint()
  end

  # A blank inbox value from a form means the default, not NULL.
  defp default_inbox(changeset) do
    if get_field(changeset, :inbox) == nil,
      do: put_change(changeset, :inbox, true),
      else: changeset
  end

  # tasks_project_id_fkey is (project_id, user_id), so another user's project
  # fails here.
  defp owned_project_constraint(changeset) do
    foreign_key_constraint(changeset, :project_id,
      name: :tasks_project_id_fkey,
      message: "must belong to you"
    )
  end
end
