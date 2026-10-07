defmodule Marskal.Imports.ReimportTest do
  use Marskal.DataCase, async: true

  import Ecto.Query

  alias Marskal.AccountsFixtures
  alias Marskal.ImportBatch
  alias Marskal.ImportItem
  alias Marskal.Imports.Applier
  alias Marskal.Imports.Parser
  alias Marskal.Projects
  alias Marskal.Tags
  alias Marskal.Tasks
  alias Marskal.Tasks.Task

  setup do
    user = AccountsFixtures.user_fixture()
    {:ok, first} = apply!(user, TodoistSnapshot.small())
    %{user: user, first: first}
  end

  test "an unchanged source changes nothing", %{user: user} do
    changes = Repo.aggregate(Marskal.Changes.Change, :count)
    {:ok, again} = apply!(user, TodoistSnapshot.small())

    assert again.stats["updated"]["tasks"] == 0
    assert again.stats["kept"] == 0
    assert Repo.aggregate(Marskal.Changes.Change, :count) == changes
  end

  test "what the source changed is applied where the user left it", %{user: user} do
    milk = task!(user, "t1")
    copy = task!(user, "t2")
    {:ok, _} = Tasks.set_notes(user, copy.id, "My notes", uuid())

    {:ok, again} =
      user
      |> apply!(
        edit_items(TodoistSnapshot.small(), %{
          "t1" => %{"content" => "Buy oat milk", "checked" => true},
          "t2" => %{"content" => "Write the copy", "description" => "Their notes"}
        })
      )

    milk = Repo.get!(Task, milk.id)
    assert milk.title == "Buy oat milk"
    assert milk.state == :done

    copy = Repo.get!(Task, copy.id)
    assert copy.title == "Write the copy"
    assert copy.notes == "My notes"

    assert again.stats["updated"]["tasks"] == 2
    assert again.stats["kept"] == 1

    assert [%{"kind" => "tasks", "title" => "Write the copy", "fields" => ["notes"]}] =
             again.stats["kept_samples"]
  end

  test "a source move takes the task to the new project", %{user: user} do
    copy = task!(user, "t2")
    child = Repo.get_by!(ImportItem, user_id: user.id, source_id: "project:p2")

    {:ok, _} =
      apply!(user, edit_items(TodoistSnapshot.small(), %{"t2" => %{"project_id" => "p2"}}))

    assert Repo.get!(Task, copy.id).project_id == child.project_id
  end

  test "the user's move wins over the source's", %{user: user} do
    copy = task!(user, "t2")
    {:ok, _} = Tasks.move_task(user, copy.id, :inbox, uuid())

    {:ok, _} =
      apply!(user, edit_items(TodoistSnapshot.small(), %{"t2" => %{"project_id" => "p2"}}))

    assert Repo.get!(Task, copy.id).inbox
  end

  test "labels merge with the user's tags", %{user: user} do
    milk = task!(user, "t1")
    {:ok, mine} = Tags.create_tag(user, %{"name" => "Mine"}, uuid())
    {:ok, _} = Tags.tag_task(user, milk.id, mine.id, uuid())

    {:ok, _} =
      apply!(user, edit_items(TodoistSnapshot.small(), %{"t1" => %{"labels" => ["Food"]}}))

    assert tag_names(user, milk) == ["Food", "Mine", "Missing recurrence"]

    {:ok, _} =
      apply!(
        user,
        edit_items(TodoistSnapshot.small(), %{"t1" => %{"labels" => ["Food", "Errand"]}})
      )

    assert tag_names(user, milk) == ["Errand", "Food", "Mine", "Missing recurrence"]
  end

  test "an item the user deleted is imported again, as a new task", %{user: user} do
    milk = task!(user, "t1")
    {:ok, _} = Tasks.delete_task(user, milk.id, uuid())

    {:ok, again} =
      apply!(user, edit_items(TodoistSnapshot.small(), %{"t1" => %{"content" => "Buy oat milk"}}))

    assert %Task{discarded_at: %DateTime{}, title: "Buy milk"} = Repo.get!(Task, milk.id)

    fresh = task!(user, "t1")
    assert fresh.id != milk.id
    assert fresh.title == "Buy oat milk"
    assert tag_names(user, fresh) == ["Errand", "Food", "Missing recurrence"]
    assert again.stats["created"]["tasks"] == 1
    assert again.stats["recreated"] == 1

    {:ok, third} =
      apply!(user, edit_items(TodoistSnapshot.small(), %{"t1" => %{"content" => "Buy oat milk"}}))

    assert third.stats["created"]["tasks"] == 0
  end

  test "a deleted project comes back with its tasks", %{user: user} do
    launch = Repo.get_by!(ImportItem, user_id: user.id, source_id: "project:p1")
    {:ok, _} = Projects.delete_project(user, launch.project_id, uuid())

    {:ok, _} = apply!(user, TodoistSnapshot.small())

    fresh = Repo.get_by!(ImportItem, user_id: user.id, source_id: "project:p1")
    assert fresh.project_id != launch.project_id
    assert task!(user, "t2").project_id == fresh.project_id
    assert task!(user, "t2").discarded_at == nil
  end

  test "a project and folder update too", %{user: user} do
    launch = Repo.get_by!(ImportItem, user_id: user.id, source_id: "project:p1")
    work = Repo.get_by!(ImportItem, user_id: user.id, source_id: "folder:fold1")

    snapshot =
      TodoistSnapshot.small()
      |> Map.update!("projects", &edit_rows(&1, %{"p1" => %{"description" => "Site and docs"}}))
      |> Map.update!("folders", &edit_rows(&1, %{"fold1" => %{"name" => "Job"}}))

    {:ok, _} = apply!(user, snapshot)

    assert Projects.get_project(user, launch.project_id).notes == "Site and docs"
    assert Marskal.ProjectFolders.get_folder(user, work.project_folder_id).name == "Job"
  end

  test "an item imported before bases were stored merges from its insert", %{user: user} do
    from(i in ImportItem, where: i.user_id == ^user.id) |> Repo.update_all(set: [fields: nil])
    editor = task!(user, "t3")

    # As the title was imported before links moved to the URL.
    Repo.update_all(from(t in Task, where: t.id == ^editor.id),
      set: [title: "[Ask editor](https://chat.example/editor)", url: nil]
    )

    Repo.update_all(
      from(c in Marskal.Changes.Change, where: c.entity_id == ^editor.id),
      set: [
        patch: %{
          "title" => "[Ask editor](https://chat.example/editor)",
          "inbox" => false,
          "project_id" => editor.project_id
        }
      ]
    )

    copy = task!(user, "t2")
    {:ok, _} = Tasks.set_notes(user, copy.id, "My notes", uuid())

    {:ok, _} = apply!(user, TodoistSnapshot.small())

    editor = Repo.get!(Task, editor.id)
    assert editor.title == "Ask editor"
    assert editor.url == "https://chat.example/editor"
    assert Repo.get!(Task, copy.id).notes == "My notes"
    assert tag_names(user, task!(user, "t1")) == ["Errand", "Food", "Missing recurrence"]
  end

  test "an import problem the user fixed stays fixed", %{user: user} do
    milk = task!(user, "t1")
    assert milk.notes =~ "- Repeat: every monday"

    problem = Enum.find(tags_of(user, milk), &(&1.name == "Missing recurrence"))
    {:ok, _} = Tags.untag_task(user, milk.id, problem.id, uuid())
    {:ok, _} = Tasks.set_notes(user, milk.id, nil, uuid())

    {:ok, _} = apply!(user, TodoistSnapshot.small())

    assert tag_names(user, milk) == ["Errand", "Food"]
    assert Repo.get!(Task, milk.id).notes == nil
  end

  test "a problem the source no longer has goes away", %{user: user} do
    milk = task!(user, "t1")

    {:ok, _} =
      apply!(
        user,
        edit_items(TodoistSnapshot.small(), %{"t1" => %{"due" => %{"date" => "2026-09-28"}}})
      )

    assert tag_names(user, milk) == ["Errand", "Food"]
    assert Repo.get!(Task, milk.id).notes == nil
  end

  defp tags_of(user, task) do
    user
    |> Tags.effective_tags([task], Tags.tree(user))
    |> Map.get(task.id, [])
    |> Enum.map(& &1.tag)
  end

  defp apply!(user, snapshot) do
    {:ok, batch} =
      %ImportBatch{}
      |> ImportBatch.changeset(%{
        user_id: user.id,
        source: "todoist",
        channel: :oauth,
        status: :pending,
        filename: "Todoist",
        payload: Jason.encode!(snapshot)
      })
      |> Repo.insert()

    batch |> then(&Parser.call/1) |> Applier.call()
  end

  defp edit_items(snapshot, edits), do: Map.update!(snapshot, "items", &edit_rows(&1, edits))

  defp edit_rows(rows, edits),
    do: Enum.map(rows, fn row -> Map.merge(row, Map.get(edits, row["id"], %{})) end)

  defp task!(user, id) do
    item = Repo.get_by!(ImportItem, user_id: user.id, source_id: "task:" <> id)
    Repo.get!(Task, item.task_id)
  end

  defp tag_names(user, task) do
    tree = Tags.tree(user)

    user
    |> Tags.effective_tags([task], tree)
    |> Map.get(task.id, [])
    |> Enum.map(& &1.tag.name)
    |> Enum.sort()
  end

  defp uuid, do: Ecto.UUID.generate()
end
