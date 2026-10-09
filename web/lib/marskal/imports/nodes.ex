defmodule Marskal.Imports.Folder do
  @moduledoc false
  # problems names what a folder could not keep, for the import summary. A
  # project or task lists `{problem, label, value}` (`Marskal.Imports.Problems`).
  defstruct [:source_id, :name, :parent_source_id, :dropped, extras: %{}, problems: []]
end

defmodule Marskal.Imports.ProjectNode do
  @moduledoc false
  defstruct [
    :source_id,
    :title,
    :notes,
    :url,
    :folder_source_id,
    :state,
    :defer_until,
    :planned,
    :due,
    :resolved_at,
    deferred_indefinitely: false,
    tag_source_ids: [],
    extras: %{},
    problems: []
  ]
end

defmodule Marskal.Imports.TaskNode do
  @moduledoc false
  defstruct [
    :source_id,
    :title,
    :notes,
    :url,
    :inbox,
    :project_source_id,
    :parent_source_id,
    :state,
    :defer_until,
    :planned,
    :due,
    :resolved_at,
    # The series attrs of a repeat the source's rule was read into, if any
    # (ADR 0007). The task becomes its first occurrence.
    :recurrence,
    deferred_indefinitely: false,
    tag_source_ids: [],
    extras: %{},
    problems: []
  ]
end

defmodule Marskal.Imports.TagNode do
  @moduledoc false
  # rank is the source's sibling order; siblings are created in that order.
  defstruct [:source_id, :name, :parent_source_id, :state, rank: 0, extras: %{}]
end
