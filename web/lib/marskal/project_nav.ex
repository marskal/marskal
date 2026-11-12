defmodule Marskal.ProjectNav do
  @moduledoc """
  Sidebar tree. `show` selects Done projects, Dropped folders, projects,
  and tags, and Deferred projects. The default shows none of those.
  A project filed under a folder that stays hidden is not hoisted into
  the list. A folder's subfolders and projects are one list in rank order
  (`Marskal.ProjectOutline`).
  Tags come as a `Marskal.Tags.Tree`. `review_due` counts the projects due
  for review (ADR 0026).
  """

  import Ecto.Query

  alias Marskal.Dates
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.Projects.Project
  alias Marskal.Repo
  alias Marskal.Tags.Tree

  defstruct [:folders, :children, :tags, show: [], review_due: 0]

  def build(user, show \\ []) when is_list(show) do
    folders =
      if :dropped in show,
        do: Marskal.ProjectFolders.list_all(user),
        else: Marskal.ProjectFolders.list_active(user)

    projects = shown_projects(user, show)

    children =
      (Enum.map(folders, &{&1.parent_id, &1}) ++
         Enum.map(projects, &{&1.project_folder_id, &1}))
      |> Enum.sort_by(fn {_parent, record} -> {record.rank, record.id} end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    %__MODULE__{
      folders: Map.new(folders, &{&1.id, &1}),
      children: children,
      tags: Marskal.Tags.tree(user),
      show: show,
      review_due: Marskal.Review.count(user)
    }
  end

  @doc "Whether this tag is in the sidebar for the nav's `show`."
  def tag_shown?(%__MODULE__{} = nav, id), do: Marskal.Tags.shown?(nav.tags, id, nav.show)

  @doc "Child tags the sidebar shows, or the shown roots for `nil`."
  def tags_in(%__MODULE__{} = nav, parent_id) do
    nav.tags
    |> Tree.children(parent_id)
    |> Enum.filter(&tag_shown?(nav, &1.id))
  end

  defp shown_projects(user, show) do
    states = [:to_do | Enum.filter(show, &(&1 in [:done, :dropped]))]
    now = DateTime.utc_now()

    Project
    |> where([p], p.user_id == ^user.id and p.state in ^states and is_nil(p.discarded_at))
    |> Repo.all()
    |> then(fn projects ->
      if :deferred in show,
        do: projects,
        else: Enum.reject(projects, &(&1.state == :to_do and Dates.deferred?(&1, now)))
    end)
  end

  @doc "Every project the nav holds, in sidebar order: depth first, by rank."
  def project_ids(%__MODULE__{} = nav), do: project_ids(nav, nil)

  defp project_ids(nav, folder_id) do
    Enum.flat_map(children(nav, folder_id), fn
      %Project{id: id} -> [id]
      %ProjectFolder{id: id} -> project_ids(nav, id)
    end)
  end

  def empty?(%__MODULE__{} = nav), do: children(nav, nil) == []

  @doc "The folders and projects in a folder id, or at the top for `nil`, in order."
  def children(%__MODULE__{} = nav, folder_id), do: Map.get(nav.children, folder_id, [])

  def folder(%__MODULE__{} = nav, id), do: Map.get(nav.folders, id)

  def child_folders(%__MODULE__{} = nav, folder),
    do: nav |> children(folder.id) |> Enum.filter(&match?(%ProjectFolder{}, &1))

  def projects_in(%__MODULE__{} = nav, folder),
    do: nav |> children(folder.id) |> Enum.filter(&match?(%Project{}, &1))

  @doc "A folder or project as `{:folder, id}` or `{:project, id}`."
  def item(%ProjectFolder{id: id}), do: {:folder, id}
  def item(%Project{id: id}), do: {:project, id}

  @doc "The folder id an item is listed in, or `:error` if it is not listed."
  def parent_id(%__MODULE__{} = nav, {:folder, id}) do
    case folder(nav, id) do
      nil -> :error
      folder -> {:ok, folder.parent_id}
    end
  end

  def parent_id(%__MODULE__{} = nav, {:project, id}) do
    Enum.find_value(nav.children, :error, fn {parent_id, records} ->
      if Enum.any?(records, &(item(&1) == {:project, id})), do: {:ok, parent_id}
    end)
  end
end
