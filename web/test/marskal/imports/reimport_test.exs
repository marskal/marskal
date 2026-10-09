defmodule Marskal.Imports.ReimportTest do
  use Marskal.DataCase, async: true

  import Ecto.Query

  alias Marskal.AccountsFixtures
  alias Marskal.ImportBatch
  alias Marskal.ImportItem
  alias Marskal.Imports.Applier
  alias Marskal.Imports.Parser
  alias Marskal.Projects
  alias Marskal.Recurrence
  alias Marskal.Recurrence.Series
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

    assert tag_names(user, milk) == ["Food", "Mine", "Missing repeat rule"]

    {:ok, _} =
      apply!(
        user,
        edit_items(TodoistSnapshot.small(), %{"t1" => %{"labels" => ["Food", "Errand"]}})
      )

    assert tag_names(user, milk) == ["Errand", "Food", "Mine", "Missing repeat rule"]
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
    assert tag_names(user, fresh) == ["Errand", "Food", "Missing repeat rule"]
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
    assert tag_names(user, task!(user, "t1")) == ["Errand", "Food", "Missing repeat rule"]
  end

  test "an import problem the user fixed stays fixed", %{user: user} do
    milk = task!(user, "t1")
    assert milk.notes =~ "- Repeat: every monday"

    problem = Enum.find(tags_of(user, milk), &(&1.name == "Missing repeat rule"))
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

  describe "flags" do
    test "a source flag is applied, and a flag the user cleared stays cleared", %{user: user} do
      assert task!(user, "t1").flagged
      refute task!(user, "t2").flagged

      {:ok, _} = Tasks.update_task(user, task!(user, "t1").id, %{flagged: false}, uuid())

      {:ok, again} =
        apply!(user, edit_items(TodoistSnapshot.small(), %{"t2" => %{"priority" => 4}}))

      refute task!(user, "t1").flagged
      assert task!(user, "t2").flagged
      assert again.stats["kept"] == 0
    end

    test "an item imported before flags merges from the default", %{user: user} do
      item = Repo.get_by!(ImportItem, user_id: user.id, source_id: "task:t2")

      item
      |> ImportItem.changeset(%{fields: Map.delete(item.fields, "flagged")})
      |> Repo.update!()

      {:ok, again} =
        apply!(user, edit_items(TodoistSnapshot.small(), %{"t2" => %{"priority" => 4}}))

      assert task!(user, "t2").flagged
      assert again.stats["kept"] == 0
    end
  end

  describe "subtasks" do
    test "a subtask is imported under its parent", %{user: user} do
      assert task!(user, "t3").parent_id == task!(user, "t2").id
    end

    test "subtasks keep their order below the parent" do
      user = AccountsFixtures.user_fixture()

      items = [
        %{
          "id" => "c1",
          "content" => "2024",
          "project_id" => "p1",
          "parent_id" => "m",
          "child_order" => 1
        },
        %{"id" => "a", "content" => "Andagter", "project_id" => "p1", "child_order" => 2},
        %{
          "id" => "c3",
          "content" => "2022",
          "project_id" => "p1",
          "parent_id" => "m",
          "child_order" => 3
        },
        %{"id" => "m", "content" => "Prædikener", "project_id" => "p1", "child_order" => 1},
        %{
          "id" => "c2",
          "content" => "2023",
          "project_id" => "p1",
          "parent_id" => "m",
          "child_order" => 2
        }
      ]

      {:ok, _} = apply!(user, Map.put(TodoistSnapshot.small(), "items", items))

      parent = task!(user, "m")
      assert parent.parent_id == nil

      assert titles(user, %{parent_id: nil, inbox: false, project_id: parent.project_id}) ==
               ["Prædikener", "Andagter"]

      assert titles(user, Tasks.Outline.children_of(parent)) == ["2024", "2023", "2022"]
    end

    test "a subtask imported flat goes under its parent on re-import", %{user: user} do
      flatten!(user, "t3")

      {:ok, again} = apply!(user, TodoistSnapshot.small())

      assert task!(user, "t3").parent_id == task!(user, "t2").id
      assert again.stats["kept"] == 0
    end

    test "the user's place in the outline wins over the source's", %{user: user} do
      ask = task!(user, "t3")
      {:ok, _} = Tasks.place_task(user, ask.id, nil, nil, uuid())

      {:ok, again} = apply!(user, TodoistSnapshot.small())

      assert task!(user, "t3").parent_id == nil
      assert again.stats["kept"] == 0
    end

    test "a parent the user put under its subtask stays there", %{user: user} do
      flatten!(user, "t3")
      ask = task!(user, "t3")
      copy = task!(user, "t2")
      {:ok, _} = Tasks.place_task(user, copy.id, ask.id, nil, uuid())

      {:ok, again} = apply!(user, TodoistSnapshot.small())

      assert task!(user, "t3").parent_id == nil
      assert task!(user, "t2").parent_id == ask.id
      assert [%{"fields" => ["parent_id"]}] = again.stats["kept_samples"]
    end
  end

  describe "repeats" do
    test "a repeat the importer reads makes the task a series' first occurrence", %{user: user} do
      milk = task!(user, "t1")
      assert milk.series_id == nil

      {:ok, _} = apply!(user, repeat_t1("every monday"))

      milk = Repo.get!(Task, milk.id)
      assert milk.occurrence_for == milk.planned_at

      assert %Series{mode: :regular, anchor: :planned, frequency: :weeks, weekdays: [1]} =
               Recurrence.get_series(user, milk.series_id)

      assert tag_names(user, milk) == ["Errand", "Food"]
      assert milk.notes == nil
    end

    test "once it repeats, the source's dates and rule leave it alone", %{user: user} do
      {:ok, _} = apply!(user, repeat_t1("every monday"))
      milk = task!(user, "t1")

      {:ok, _} = apply!(user, repeat_t1("every tuesday", "2026-10-06"))

      again = Repo.get!(Task, milk.id)
      assert again.planned_at == milk.planned_at
      assert again.series_id == milk.series_id
      assert Recurrence.get_series(user, milk.series_id).weekdays == [1]
    end

    test "a first import makes the series too, and every! repeats after completion" do
      user = AccountsFixtures.user_fixture()
      {:ok, _} = apply!(user, repeat_t1("every! 3 days"))

      milk = task!(user, "t1")

      assert %Series{mode: :on_completion, frequency: :days, interval: 3} =
               Recurrence.get_series(user, milk.series_id)
    end

    test "a repeat with no date stays a problem", %{user: user} do
      snapshot =
        edit_items(TodoistSnapshot.small(), %{
          "t1" => %{"due" => %{"string" => "every monday", "is_recurring" => true}}
        })

      {:ok, _} = apply!(user, snapshot)

      assert task!(user, "t1").series_id == nil
      assert "Missing repeat rule" in tag_names(user, task!(user, "t1"))
    end
  end

  defp repeat_t1(string, date \\ "2026-09-28") do
    edit_items(TodoistSnapshot.small(), %{
      "t1" => %{"due" => %{"date" => date, "string" => string, "is_recurring" => true}}
    })
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

  # As a task was imported before subtasks were: at the top, with a base
  # that predates the parent.
  defp flatten!(user, id) do
    task = task!(user, id)
    Repo.update_all(from(t in Task, where: t.id == ^task.id), set: [parent_id: nil])

    item = Repo.get_by!(ImportItem, user_id: user.id, source_id: "task:" <> id)

    item
    |> ImportItem.changeset(%{fields: Map.delete(item.fields, "parent_id")})
    |> Repo.update!()
  end

  defp titles(user, group) do
    from(t in Task,
      where: t.user_id == ^user.id and t.inbox == ^group.inbox and is_nil(t.discarded_at),
      order_by: [asc: t.rank]
    )
    |> where_group(group)
    |> select([t], t.title)
    |> Repo.all()
  end

  defp where_group(query, %{parent_id: nil, project_id: project_id}),
    do: where(query, [t], is_nil(t.parent_id) and t.project_id == ^project_id)

  defp where_group(query, %{parent_id: parent_id}),
    do: where(query, [t], t.parent_id == ^parent_id)

  defp uuid, do: Ecto.UUID.generate()
end
