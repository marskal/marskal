defmodule Marskal.StructureTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.ProjectFolders
  alias Marskal.ProjectNav
  alias Marskal.Projects
  alias Marskal.Tasks

  setup do
    %{user: AccountsFixtures.user_fixture(), other: AccountsFixtures.user_fixture()}
  end

  test "a nested folder remembers the path of its ancestors", %{user: user} do
    {:ok, work} = ProjectFolders.create_folder(user, %{"name" => "Work"}, command())
    {:ok, client} = ProjectFolders.create_folder(user, %{"name" => "Client A", "parent_id" => work.id}, command())

    assert client.parent_path == ["Work"]

    {:ok, _} = ProjectFolders.rename_folder(user, work.id, "Studio", command())
    client = ProjectFolders.get_folder(user, client.id)
    assert client.parent_path == ["Studio"]
  end

  test "a folder cannot be moved under its own child", %{user: user} do
    {:ok, work} = ProjectFolders.create_folder(user, %{"name" => "Work"}, command())
    {:ok, child} = ProjectFolders.create_folder(user, %{"name" => "Child", "parent_id" => work.id}, command())

    assert {:error, changeset} = ProjectFolders.reparent_folder(user, work.id, child.id, command())
    assert "would create a cycle" in errors_on(changeset).parent_id
  end

  test "a project cannot be filed in someone else's folder", %{user: user, other: other} do
    {:ok, folder} = ProjectFolders.create_folder(other, %{"name" => "Theirs"}, command())

    assert {:error, changeset} =
             Projects.create_project(user, %{"title" => "Mine", "project_folder_id" => folder.id}, command())

    assert "must belong to you" in errors_on(changeset).project_folder_id
  end

  test "dropped folders leave the sidebar and do not hoist their projects", %{user: user} do
    {:ok, archive} = ProjectFolders.create_folder(user, %{"name" => "Old archive"}, command())
    {:ok, _project} = Projects.create_project(user, %{"title" => "Abandoned blog", "project_folder_id" => archive.id}, command())
    {:ok, _} = ProjectFolders.drop_folder(user, archive.id, command())

    nav = ProjectNav.build(user)
    assert ProjectNav.root_folders(nav) == []
    assert ProjectNav.unfiled_projects(nav) == []
  end

  test "a task filed on a project shows on that project, not in the inbox", %{user: user} do
    {:ok, project} = Projects.create_project(user, %{"title" => "Launch website"}, command())

    {:ok, task} =
      Tasks.create_task(user, %{"title" => "Draft homepage copy", "project_id" => project.id, "inbox" => false}, command())

    assert Enum.map(Tasks.list_project_tasks(user, project.id), & &1.id) == [task.id]
    assert Tasks.list_inbox(user) == []
  end

  defp command, do: Ecto.UUID.generate()
end
