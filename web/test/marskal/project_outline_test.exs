defmodule Marskal.ProjectOutlineTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.ProjectFolders
  alias Marskal.ProjectNav
  alias Marskal.ProjectOutline
  alias Marskal.Projects
  alias Marskal.Sync

  setup do
    %{user: AccountsFixtures.user_fixture()}
  end

  # The sidebar's top list, as items.
  defp top(user, folder_id \\ nil) do
    user |> ProjectNav.build() |> ProjectNav.children(folder_id) |> Enum.map(&ProjectNav.item/1)
  end

  defp folder(user, name, parent_id \\ nil) do
    {:ok, folder} =
      ProjectFolders.create_folder(user, %{"name" => name, "parent_id" => parent_id}, command())

    folder
  end

  defp project(user, title, folder_id \\ nil) do
    {:ok, project} =
      Projects.create_project(
        user,
        %{"title" => title, "project_folder_id" => folder_id},
        command()
      )

    project
  end

  test "folders and projects share one order, new ones last", %{user: user} do
    a = project(user, "Zebra")
    b = folder(user, "Work")
    c = project(user, "Apple")

    assert top(user) == [{:project, a.id}, {:folder, b.id}, {:project, c.id}]
  end

  test "a drop puts a project between folders, and in a folder", %{user: user} do
    work = folder(user, "Work")
    home = folder(user, "Home")
    launch = project(user, "Launch")

    {:ok, _} =
      ProjectOutline.place(user, {:project, launch.id}, nil, {:folder, work.id}, command())

    assert top(user) == [{:folder, work.id}, {:project, launch.id}, {:folder, home.id}]

    {:ok, moved} = ProjectOutline.place(user, {:project, launch.id}, home.id, nil, command())
    assert moved.project_folder_id == home.id
    assert top(user, home.id) == [{:project, launch.id}]

    {:ok, _} = ProjectOutline.place(user, {:folder, work.id}, home.id, :last, command())
    assert top(user, home.id) == [{:project, launch.id}, {:folder, work.id}]
    assert ProjectFolders.get_folder(user, work.id).parent_path == ["Home"]
  end

  test "a drop next to something in another folder is refused", %{user: user} do
    work = folder(user, "Work")
    inside = project(user, "Inside", work.id)
    loose = project(user, "Loose")

    assert {:error, :not_a_sibling} =
             ProjectOutline.place(
               user,
               {:project, loose.id},
               nil,
               {:project, inside.id},
               command()
             )
  end

  test "a folder cannot go inside itself", %{user: user} do
    work = folder(user, "Work")
    client = folder(user, "Client", work.id)

    assert {:error, %Ecto.Changeset{}} =
             ProjectOutline.place(user, {:folder, work.id}, client.id, nil, command())
  end

  test "indent files under the folder above, never under a project", %{user: user} do
    work = folder(user, "Work")
    launch = project(user, "Launch")
    report = project(user, "Report")

    {:ok, _} = ProjectOutline.indent(user, {:project, launch.id}, command())
    assert top(user) == [{:folder, work.id}, {:project, report.id}]
    assert top(user, work.id) == [{:project, launch.id}]

    assert {:error, :not_a_folder} =
             ProjectOutline.indent(user, {:folder, folder(user, "Home").id}, command())

    assert {:error, :first} = ProjectOutline.indent(user, {:folder, work.id}, command())
  end

  test "outdent puts it right after its folder", %{user: user} do
    work = folder(user, "Work")
    home = folder(user, "Home")
    launch = project(user, "Launch", work.id)

    {:ok, _} = ProjectOutline.outdent(user, {:project, launch.id}, command())
    assert top(user) == [{:folder, work.id}, {:project, launch.id}, {:folder, home.id}]
    assert {:error, :top_level} = ProjectOutline.outdent(user, {:project, launch.id}, command())
  end

  test "up and down swap with the shown neighbor, past done projects", %{user: user} do
    a = project(user, "A")
    done = project(user, "Done")
    b = folder(user, "B")
    {:ok, _} = Projects.complete_project(user, done.id, command())

    {:ok, _} = ProjectOutline.move_down(user, {:project, a.id}, command())
    assert top(user) == [{:folder, b.id}, {:project, a.id}]

    {:ok, _} = ProjectOutline.move_up(user, {:project, a.id}, command())
    assert top(user) == [{:project, a.id}, {:folder, b.id}]

    assert {:error, :first} = ProjectOutline.move_up(user, {:project, a.id}, command())
    assert {:error, :last} = ProjectOutline.move_down(user, {:folder, b.id}, command())
  end

  test "filing a project elsewhere without a rank puts it last there", %{user: user} do
    work = folder(user, "Work")
    first = project(user, "First", work.id)
    moved = project(user, "Moved")

    {:ok, _} = Projects.update_project(user, moved.id, %{project_folder_id: work.id}, command())
    assert top(user, work.id) == [{:project, first.id}, {:project, moved.id}]
  end

  test "the rank syncs, and a client cannot write it", %{user: user} do
    work = folder(user, "Work")
    launch = project(user, "Launch", work.id)

    %{rows: rows} = Sync.pull(user, nil)
    assert [%{"rank" => rank}] = rows["project_folder"]
    assert rank == work.rank
    assert [%{"rank" => _}] = rows["project"]

    refute "rank" in Marskal.Projects.Project.client_fields(:patch)
    refute "rank" in Marskal.ProjectFolders.ProjectFolder.client_fields(:patch)
    assert launch.rank
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
