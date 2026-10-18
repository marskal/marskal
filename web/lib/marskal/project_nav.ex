defmodule Marskal.ProjectNav do
  @moduledoc """
  Sidebar tree. Dropped folders and done or dropped projects stay out.
  A project filed under a dropped ancestor is not hoisted into the list.
  A folder's subfolders and projects are one list in rank order
  (`Marskal.ProjectOutline`).
  Tags come as a `Marskal.Tags.Tree`; dropped subtrees are hidden.
  """

  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.Projects.Project
  alias Marskal.Tags.Tree

  defstruct [:folders, :children, :tags]

  def build(user) do
    folders = Marskal.ProjectFolders.list_active(user)
    projects = Marskal.Projects.list_open(user)

    children =
      (Enum.map(folders, &{&1.parent_id, &1}) ++
         Enum.map(projects, &{&1.project_folder_id, &1}))
      |> Enum.sort_by(fn {_parent, record} -> {record.rank, record.id} end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    %__MODULE__{
      folders: Map.new(folders, &{&1.id, &1}),
      children: children,
      tags: Marskal.Tags.tree(user)
    }
  end

  @doc "Visible child tags of a tag, or the visible roots for `nil`."
  def tags_in(%__MODULE__{tags: tree}, parent_id) do
    tree |> Tree.children(parent_id) |> Enum.filter(&Tree.visible?(tree, &1.id))
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
