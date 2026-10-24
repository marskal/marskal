defmodule Marskal.GoTo do
  @moduledoc """
  Go to a folder, project, or tag by name (ADR 0033).

  Targets are every live folder, project, and tag, whatever the sidebar
  shows, each with its path: a folder's or project's folders and its own
  name, a tag's ancestors and its name. They match as `Marskal.PathSearch`
  describes. The caller may add targets of its own, such as the views.

  A target the sidebar hides, for being Done, Dropped, or Deferred, ranks
  after one it shows.
  """

  alias Marskal.PathSearch
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.ProjectNav
  alias Marskal.Projects.Project
  alias Marskal.Tags
  alias Marskal.Tags.Tag
  alias Marskal.Tags.Tree

  @limit 20
  @kinds %{view: 0, project: 1, folder: 2, tag: 3}

  defmodule Target do
    @moduledoc "Somewhere to go: `id` is a record's id, or the caller's key for a view."
    defstruct [:type, :id, :path, :state, hidden: false]
  end

  @doc """
  The user's folders, projects, and tags, in sidebar order. `shown` is the
  sidebar as it is (`Marskal.ProjectNav.build/2`); what it leaves out is
  marked hidden.
  """
  def targets(user, %ProjectNav{} = shown) do
    all = ProjectNav.build(user, [:done, :dropped, :deferred])
    outline(all, shown, nil, []) ++ tags(all.tags, shown)
  end

  defp outline(all, shown, folder_id, ancestors) do
    all
    |> ProjectNav.children(folder_id)
    |> Enum.flat_map(fn
      %ProjectFolder{} = folder ->
        path = ancestors ++ [folder.name]

        [
          %Target{
            type: :folder,
            id: folder.id,
            path: path,
            state: folder.state,
            hidden: ProjectNav.folder(shown, folder.id) == nil
          }
          | outline(all, shown, folder.id, path)
        ]

      %Project{} = project ->
        [
          %Target{
            type: :project,
            id: project.id,
            path: ancestors ++ [project.title],
            state: project.state,
            hidden: ProjectNav.parent_id(shown, {:project, project.id}) == :error
          }
        ]
    end)
  end

  defp tags(tree, shown) do
    tree
    |> Tree.all()
    |> Enum.filter(&Tags.shown?(tree, &1.id, [:dropped]))
    |> Enum.map(fn tag ->
      %Target{
        type: :tag,
        id: tag.id,
        path: Tag.path(tag),
        state: Tree.state(tree, tag.id),
        hidden: not ProjectNav.tag_shown?(shown, tag.id)
      }
    end)
  end

  @doc """
  The targets that match, best first: an exact name, then shown before
  hidden, then fewer skipped path segments, then views, projects, folders,
  and tags in that order, then shallower, then the order given.
  """
  def run(targets, query, limit \\ @limit) do
    pieces = PathSearch.pieces(query)
    whole = PathSearch.whole(query)

    if pieces == [] do
      []
    else
      targets
      |> Enum.with_index()
      |> Enum.flat_map(&ranked(&1, pieces, whole))
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.take(limit)
      |> Enum.map(&elem(&1, 1))
    end
  end

  defp ranked({target, index}, pieces, whole) do
    case PathSearch.match(target.path, pieces) do
      nil -> []
      skipped -> [{rank(target, whole, skipped, index), target}]
    end
  end

  defp rank(target, whole, skipped, index) do
    exact = if PathSearch.exact?(List.last(target.path), whole), do: 0, else: 1
    hidden = if target.hidden, do: 1, else: 0
    {exact, hidden, skipped, Map.fetch!(@kinds, target.type), length(target.path), index}
  end
end
