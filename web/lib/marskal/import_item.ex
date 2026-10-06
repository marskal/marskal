defmodule Marskal.ImportItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false, read_after_writes: true}
  @foreign_key_type Ecto.UUID

  schema "import_items" do
    field :source, :string
    field :kind, Ecto.Enum, values: [:folder, :project, :task, :tag]
    field :source_id, :string
    field :extras, :map, default: %{}
    # What the source said last, per merged field (Marskal.Imports.Merge).
    field :fields, :map

    belongs_to :import_batch, Marskal.ImportBatch
    belongs_to :user, Marskal.Accounts.User
    belongs_to :project_folder, Marskal.ProjectFolders.ProjectFolder
    belongs_to :project, Marskal.Projects.Project
    belongs_to :task, Marskal.Tasks.Task
    belongs_to :tag, Marskal.Tags.Tag

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :import_batch_id,
      :user_id,
      :source,
      :kind,
      :source_id,
      :extras,
      :fields,
      :project_folder_id,
      :project_id,
      :task_id,
      :tag_id
    ])
    |> validate_required([:import_batch_id, :user_id, :source, :kind, :source_id])
    |> unique_constraint([:user_id, :source, :source_id],
      name: :import_items_user_source_source_id_index
    )
  end
end
