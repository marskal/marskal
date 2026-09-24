defmodule Marskal.Imports.ApplierTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.ImportBatch
  alias Marskal.ImportItem
  alias Marskal.Imports.Applier
  alias Marskal.Imports.Parser
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.Projects.Project
  alias Marskal.Tasks
  alias Marskal.Tasks.Task

  setup do
    %{user: AccountsFixtures.user_fixture(), other: AccountsFixtures.user_fixture()}
  end

  test "creates folders projects and tasks for the user", %{user: user} do
    batch = preview!(user, OmnifocusBackup.compact_backup(), "OmniFocus.ofocus-backup")
    assert batch.status == :previewed

    assert {:ok, batch} = Applier.call(batch)
    assert batch.status == :applied

    work = folder!(batch, "folderWork00")
    assert work.name == "Work"
    dropped = folder!(batch, "folderOld000")
    assert dropped.state == :dropped

    project = project!(batch, "projSite0000")
    assert project.title == "Launch website"
    assert project.project_folder_id == work.id
    assert project.state == :to_do
    assert project.notes == "Public site"

    draft = task!(batch, "taskDraft000")
    refute draft.inbox
    assert draft.project_id == project.id
    assert draft.state == :to_do

    milk = task!(batch, "taskInbox000")
    assert milk.inbox
    assert milk.project_id == nil

    done = task!(batch, "taskDone0000")
    assert done.state == :done
  end

  test "second import skips existing source ids", %{user: user} do
    batch = preview!(user, OmnifocusBackup.compact_backup(), "OmniFocus.ofocus-backup")
    assert {:ok, _} = Applier.call(batch)
    created = task_items(user)

    batch2 = preview!(user, OmnifocusBackup.compact_backup(), "OmniFocus.ofocus-backup")
    assert {:ok, batch2} = Applier.call(batch2)

    assert task_items(user) == created
    assert batch2.stats["created"]["tasks"] == 0
    assert batch2.stats["skipped"]["tasks"] > 0
  end

  test "applies an OmniFocus 4.9 tutorial backup", %{user: user} do
    batch =
      preview!(user, OmnifocusBackup.tutorial_backup(), "omnifocus-tutorial.ofocus-backup.zip")

    assert batch.status == :previewed
    assert batch.stats["projects"] == 2
    assert batch.stats["tasks"] >= 20

    assert {:ok, applied} = Applier.call(batch)
    assert applied.status == :applied

    tutorial = Repo.get_by!(Project, user_id: user.id, title: "Get to know OmniFocus 4 for Mac")
    titles = user |> Tasks.list_project_tasks(tutorial.id) |> Enum.map(& &1.title)
    assert "Click this action" in titles

    brokka = Repo.get_by!(Project, user_id: user.id, title: "Brokkassen")

    brokka_titles =
      user |> Tasks.list_project_tasks(brokka.id) |> Enum.map(& &1.title) |> Enum.sort()

    assert brokka_titles == ["Gør noget", "Gør noget andet"]

    done = Repo.get_by!(Task, user_id: user.id, title: "Create a project")
    assert done.state == :done

    inspector = Repo.get_by!(Task, user_id: user.id, title: "Check out the Inspector")
    assert inspector.notes =~ "Click the Inspect button"
    refute inspector.notes =~ "AppleSystemUIFont"
  end

  test "does not import into another user", %{user: user, other: other} do
    batch = preview!(user, OmnifocusBackup.compact_backup(), "OmniFocus.ofocus-backup")
    assert {:ok, _} = Applier.call(batch)

    refute Repo.get_by(Task, user_id: other.id, title: "Buy milk")
    refute Repo.get_by(Project, user_id: other.id, title: "Launch website")
  end

  defp preview!(user, bytes, filename) do
    {:ok, batch} =
      %ImportBatch{}
      |> ImportBatch.changeset(%{
        user_id: user.id,
        source: "omnifocus",
        channel: :file,
        status: :pending,
        filename: filename,
        payload: bytes
      })
      |> Repo.insert()

    Parser.call(batch)
  end

  defp folder!(batch, source_id) do
    item = item!(batch, source_id)
    Repo.get!(ProjectFolder, item.project_folder_id)
  end

  defp project!(batch, source_id) do
    item = item!(batch, source_id)
    Repo.get!(Project, item.project_id)
  end

  defp task!(batch, source_id) do
    item = item!(batch, source_id)
    Repo.get!(Task, item.task_id)
  end

  defp item!(batch, source_id) do
    Repo.get_by!(ImportItem, import_batch_id: batch.id, source_id: source_id)
  end

  defp task_items(user) do
    Repo.aggregate(
      from(i in ImportItem, where: i.user_id == ^user.id and i.kind == :task),
      :count
    )
  end
end
