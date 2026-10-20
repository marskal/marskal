defmodule Marskal.StructureTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.Changes.Change
  alias Marskal.ProjectFolders
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.ProjectNav
  alias Marskal.Projects
  alias Marskal.Repo
  alias Marskal.Tasks

  setup do
    %{user: AccountsFixtures.user_fixture(), other: AccountsFixtures.user_fixture()}
  end

  test "a nested folder remembers the path of its ancestors", %{user: user} do
    {:ok, work} = ProjectFolders.create_folder(user, %{"name" => "Work"}, command())

    {:ok, client} =
      ProjectFolders.create_folder(
        user,
        %{"name" => "Client A", "parent_id" => work.id},
        command()
      )

    assert client.parent_path == ["Work"]

    {:ok, _} = ProjectFolders.rename_folder(user, work.id, "Studio", command())
    client = ProjectFolders.get_folder(user, client.id)
    assert client.parent_path == ["Studio"]
  end

  test "a folder cannot be moved under its own child", %{user: user} do
    {:ok, work} = ProjectFolders.create_folder(user, %{"name" => "Work"}, command())

    {:ok, child} =
      ProjectFolders.create_folder(user, %{"name" => "Child", "parent_id" => work.id}, command())

    assert {:error, changeset} =
             ProjectFolders.reparent_folder(user, work.id, child.id, command())

    assert "would create a cycle" in errors_on(changeset).parent_id
  end

  test "a project cannot be filed in someone else's folder", %{user: user, other: other} do
    {:ok, folder} = ProjectFolders.create_folder(other, %{"name" => "Theirs"}, command())

    assert {:error, changeset} =
             Projects.create_project(
               user,
               %{"title" => "Mine", "project_folder_id" => folder.id},
               command()
             )

    assert "must belong to you" in errors_on(changeset).project_folder_id
  end

  test "dropped folders leave the sidebar and do not hoist their projects", %{user: user} do
    {:ok, archive} = ProjectFolders.create_folder(user, %{"name" => "Old archive"}, command())

    {:ok, _project} =
      Projects.create_project(
        user,
        %{"title" => "Abandoned blog", "project_folder_id" => archive.id},
        command()
      )

    {:ok, _} = ProjectFolders.drop_folder(user, archive.id, command())

    nav = ProjectNav.build(user)
    assert ProjectNav.children(nav, nil) == []
    assert MarskalWeb.NavOutline.project_rows(nav, nil) == []
  end

  test "a task filed on a project shows on that project, not in the inbox", %{user: user} do
    {:ok, project} = Projects.create_project(user, %{"title" => "Launch website"}, command())

    {:ok, task} =
      Tasks.create_task(
        user,
        %{"title" => "Draft homepage copy", "project_id" => project.id, "inbox" => false},
        command()
      )

    assert Enum.map(Tasks.list_project_tasks(user, project.id), & &1.id) == [task.id]
    assert Tasks.list_inbox(user) == []
  end

  describe "deleting a folder" do
    test "discards its subfolders and unfiles their projects", %{user: user} do
      {:ok, work} = ProjectFolders.create_folder(user, %{"name" => "Work"}, command())

      {:ok, client} =
        ProjectFolders.create_folder(
          user,
          %{"name" => "Client", "parent_id" => work.id},
          command()
        )

      {:ok, site} =
        Projects.create_project(
          user,
          %{"title" => "Site", "project_folder_id" => client.id},
          command()
        )

      delete = command()
      {:ok, discarded} = ProjectFolders.delete_folder(user, work.id, delete)

      assert %DateTime{} = discarded.discarded_at
      assert ProjectFolders.list_all(user) == []
      assert ProjectFolders.get_folder(user, client.id) == nil
      assert Repo.get!(ProjectFolder, client.id).discarded_at

      site = Projects.get_project(user, site.id)
      assert site.project_folder_id == nil
      assert site.discarded_at == nil

      changes = Repo.all(from c in Change, where: c.user_id == ^user.id, select: c.entity_id)
      assert work.id in changes and client.id in changes

      count = Repo.aggregate(Change, :count)
      assert {:ok, _} = ProjectFolders.delete_folder(user, work.id, delete)
      assert Repo.aggregate(Change, :count) == count
    end

    test "a discarded folder takes no patches, subfolders, or projects", %{user: user} do
      {:ok, gone} = ProjectFolders.create_folder(user, %{"name" => "Gone"}, command())
      {:ok, _} = ProjectFolders.delete_folder(user, gone.id, command())

      assert {:error, :not_found} = ProjectFolders.rename_folder(user, gone.id, "Back", command())

      assert {:error, changeset} =
               ProjectFolders.create_folder(
                 user,
                 %{"name" => "Child", "parent_id" => gone.id},
                 command()
               )

      assert "must belong to you" in errors_on(changeset).parent_id

      assert {:error, changeset} =
               Projects.create_project(
                 user,
                 %{"title" => "Filed", "project_folder_id" => gone.id},
                 command()
               )

      assert "must belong to you" in errors_on(changeset).project_folder_id
    end
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
