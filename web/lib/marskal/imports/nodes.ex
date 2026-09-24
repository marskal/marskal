defmodule Marskal.Imports.Folder do
  @moduledoc false
  defstruct [:source_id, :name, :parent_source_id, :dropped, extras: %{}]
end

defmodule Marskal.Imports.ProjectNode do
  @moduledoc false
  defstruct [:source_id, :title, :notes, :folder_source_id, :state, extras: %{}]
end

defmodule Marskal.Imports.TaskNode do
  @moduledoc false
  defstruct [
    :source_id,
    :title,
    :notes,
    :inbox,
    :project_source_id,
    :parent_source_id,
    :state,
    extras: %{}
  ]
end
