defmodule Marskal.ProjectNav do
  @moduledoc """
  Sidebar tree. Dropped folders and done or dropped projects stay out.
  A project filed under a dropped ancestor is not hoisted into the list.
  """

  defstruct [:folders_by_parent, :projects_by_folder]

  def build(user) do
    folders = Marskal.ProjectFolders.list_active(user)
    projects = Marskal.Projects.list_open(user)

    %__MODULE__{
      folders_by_parent: Enum.group_by(folders, & &1.parent_id),
      projects_by_folder: Enum.group_by(projects, & &1.project_folder_id)
    }
  end

  def empty?(%__MODULE__{} = nav) do
    root_folders(nav) == [] and unfiled_projects(nav) == []
  end

  def root_folders(%__MODULE__{} = nav), do: Map.get(nav.folders_by_parent, nil, [])
  def child_folders(%__MODULE__{} = nav, folder), do: Map.get(nav.folders_by_parent, folder.id, [])
  def projects_in(%__MODULE__{} = nav, folder), do: Map.get(nav.projects_by_folder, folder.id, [])
  def unfiled_projects(%__MODULE__{} = nav), do: Map.get(nav.projects_by_folder, nil, [])
end
