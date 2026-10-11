defmodule Marskal.SyncPushTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.ProjectFolders
  alias Marskal.Projects
  alias Marskal.Sync
  alias Marskal.Sync.Push
  alias Marskal.Tags
  alias Marskal.Tags.Link
  alias Marskal.Tags.Tag
  alias Marskal.Tasks
  alias Marskal.Tasks.Task

  setup do
    %{user: AccountsFixtures.user_fixture(), other: AccountsFixtures.user_fixture()}
  end

  describe "results" do
    test "applied, then replayed for the same command id", %{user: user} do
      id = uuid()
      add = insert("task", id, %{"title" => "Bread", "inbox" => true})

      assert [%{status: "applied"}] = Push.push(user, [add])
      assert %Task{title: "Bread", inbox: true, state: :to_do} = Tasks.get_task(user, id)

      assert [%{status: "replayed"}] = Push.push(user, [add])
      assert [_] = Tasks.list_inbox(user)
    end

    test "noop when nothing changes", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{title: "Milk"}, uuid())
      assert [%{status: "noop"}] = Push.push(user, [patch("task", task.id, %{"title" => "Milk"})])
    end

    test "in order, each with its own result", %{user: user} do
      id = uuid()

      results =
        Push.push(user, [
          insert("task", id, %{"title" => "Eggs"}),
          patch("task", id, %{"title" => "Eggs, a dozen"}),
          patch("task", id, %{"state" => "done"}),
          patch("task", uuid(), %{"title" => "Nobody"})
        ])

      assert Enum.map(results, & &1.status) == ~w(applied applied applied rejected)
      assert %Task{title: "Eggs, a dozen", state: :done} = Repo.get!(Task, id)
    end
  end

  test "a client sets and clears a URL", %{user: user} do
    id = uuid()

    assert [%{status: "applied"}, %{status: "applied"}] =
             Push.push(user, [
               insert("task", id, %{"title" => "Read", "url" => "https://a.example"}),
               patch("task", id, %{"url" => "https://b.example"})
             ])

    assert Tasks.get_task(user, id).url == "https://b.example"

    assert [%{status: "rejected"}] =
             Push.push(user, [patch("task", id, %{"url" => "javascript:x"})])

    assert [%{status: "applied"}] = Push.push(user, [patch("task", id, %{"url" => nil})])
    assert Tasks.get_task(user, id).url == nil
  end

  test "a client flags a task and a project", %{user: user} do
    task = uuid()
    project = uuid()

    assert [%{status: "applied"}, %{status: "applied"}, %{status: "applied"}] =
             Push.push(user, [
               insert("project", project, %{"title" => "Home", "flagged" => true}),
               insert("task", task, %{"title" => "Call"}),
               patch("task", task, %{"flagged" => true})
             ])

    assert Tasks.get_task(user, task).flagged
    assert Projects.get_project(user, project).flagged

    rows = Sync.pull(user, nil).rows
    assert [%{"flagged" => true}] = rows["task"]
    assert [%{"flagged" => true}] = rows["project"]
  end

  describe "rejected" do
    test "a field outside the allow-list", %{user: user} do
      id = uuid()

      for fields <- [
            %{"title" => "X", "user_id" => user.id},
            %{"title" => "X", "resolved_at" => now()}
          ] do
        assert [%{status: "rejected", reason: "field_not_allowed"}] =
                 Push.push(user, [insert("task", id, fields)])
      end

      assert Repo.get(Task, id) == nil
    end

    test "another user's row, or one that is not there", %{user: user, other: other} do
      {:ok, theirs} = Tasks.create_task(other, %{title: "Theirs"}, uuid())

      assert [%{status: "rejected", reason: "not_found"}] =
               Push.push(user, [patch("task", theirs.id, %{"title" => "Mine"})])

      assert [%{status: "rejected", reason: "exists"}] =
               Push.push(user, [insert("task", theirs.id, %{"title" => "Mine"})])

      assert Repo.get!(Task, theirs.id).title == "Theirs"
    end

    test "a failed validation, with the errors", %{user: user} do
      assert [%{status: "rejected", reason: "invalid", errors: %{title: [_]}}] =
               Push.push(user, [insert("task", uuid(), %{"title" => ""})])
    end

    test "a malformed command", %{user: user} do
      assert [
               %{reason: "invalid_command"},
               %{reason: "unknown_entity"},
               %{reason: "invalid_op"}
             ] =
               Push.push(user, [
                 %{"id" => "nope", "entity" => "task", "entity_id" => uuid(), "op" => "patch"},
                 %{insert("task", uuid(), %{}) | "entity" => "user"},
                 %{insert("task", uuid(), %{}) | "op" => "delete"}
               ])
    end
  end

  describe "discard" do
    test "a patch of discarded_at deletes, and wins over the rest of it", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{title: "Oops"}, uuid())

      assert [%{status: "applied"}] =
               Push.push(user, [
                 patch("task", task.id, %{"discarded_at" => now(), "title" => "Renamed"})
               ])

      assert %Task{title: "Oops", discarded_at: %DateTime{}} = Repo.get!(Task, task.id)

      assert [%{status: "rejected", reason: "not_found"}] =
               Push.push(user, [patch("task", task.id, %{"title" => "Stale edit"})])

      assert [%{status: "rejected", reason: "not_found"}] =
               Push.push(user, [patch("task", task.id, %{"discarded_at" => nil})])
    end

    test "a folder, its subfolders going with it", %{user: user} do
      {:ok, folder} = ProjectFolders.create_folder(user, %{name: "Old"}, uuid())

      {:ok, _} =
        ProjectFolders.create_folder(user, %{name: "Older", parent_id: folder.id}, uuid())

      assert [%{status: "applied"}] =
               Push.push(user, [patch("project_folder", folder.id, %{"discarded_at" => now()})])

      assert ProjectFolders.list_all(user) == []
    end
  end

  describe "resolved_at" do
    test "takes the client's time inside the skew window", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{title: "Milk"}, uuid())
      an_hour_ago = DateTime.add(DateTime.utc_now(:second), -1, :hour)

      Push.push(user, [
        patch("task", task.id, %{"state" => "done"}, DateTime.to_iso8601(an_hour_ago))
      ])

      assert Repo.get!(Task, task.id).resolved_at == an_hour_ago
    end

    test "and receipt time outside it", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, uuid())
      last_week = DateTime.add(DateTime.utc_now(), -7, :day)

      Push.push(user, [
        patch("project", project.id, %{"state" => "dropped"}, DateTime.to_iso8601(last_week))
      ])

      resolved_at = Projects.get_project(user, project.id).resolved_at
      assert DateTime.diff(DateTime.utc_now(), resolved_at) in 0..5
    end
  end

  describe "outline" do
    test "a subtask lives where its parent does, at the rank the client gave", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Trip"}, uuid())

      {:ok, parent} =
        Tasks.create_task(user, %{title: "Pack", project_id: project.id, inbox: false}, uuid())

      id = uuid()

      assert [%{status: "applied"}] =
               Push.push(user, [
                 insert("task", id, %{"title" => "Socks", "parent_id" => parent.id, "rank" => "m"})
               ])

      assert %Task{parent_id: parent_id, project_id: project_id, inbox: false, rank: "m"} =
               Repo.get!(Task, id)

      assert parent_id == parent.id and project_id == project.id
    end

    test "a patch moves a task under another, bringing its location", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Trip"}, uuid())

      {:ok, parent} =
        Tasks.create_task(user, %{title: "Pack", project_id: project.id, inbox: false}, uuid())

      {:ok, loose} = Tasks.create_task(user, %{title: "Charger"}, uuid())

      assert [%{status: "applied"}] =
               Push.push(user, [
                 patch("task", loose.id, %{"parent_id" => parent.id, "rank" => "t"})
               ])

      assert %Task{project_id: project_id, inbox: false, rank: "t"} = Repo.get!(Task, loose.id)
      assert project_id == project.id

      assert [%{status: "rejected", reason: "cycle"}] =
               Push.push(user, [patch("task", parent.id, %{"parent_id" => loose.id})])
    end

    test "a bad rank is rejected", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{title: "A"}, uuid())

      assert [%{status: "rejected"}] =
               Push.push(user, [patch("task", task.id, %{"rank" => nil})])

      assert [%{status: "rejected", reason: "invalid"}] =
               Push.push(user, [patch("task", task.id, %{"rank" => "!"})])
    end
  end

  describe "tags" do
    test "a duplicate name merges into the tag already there", %{user: user} do
      {:ok, waiting} = Tags.create_tag(user, %{name: "Waiting"}, uuid())
      {:ok, task} = Tasks.create_task(user, %{title: "Reply"}, uuid())
      duplicate = uuid()

      assert [%{status: "applied"}, %{status: "applied"}] =
               Push.push(user, [
                 insert("tag", duplicate, %{"name" => "waiting"}),
                 insert("task_tag", Link.id(:task, task.id, duplicate), %{
                   "task_id" => task.id,
                   "tag_id" => duplicate
                 })
               ])

      assert %Tag{discarded_at: %DateTime{}, merged_into_id: into} = Repo.get!(Tag, duplicate)
      assert into == waiting.id
      assert [%{"tag_id" => tag_id}] = Sync.pull(user, nil).rows["task_tag"]
      assert tag_id == waiting.id
    end

    test "a link's id must be the one of its pair; patching it untags and tags again",
         %{user: user} do
      {:ok, tag} = Tags.create_tag(user, %{name: "Shop"}, uuid())
      {:ok, task} = Tasks.create_task(user, %{title: "Milk"}, uuid())
      fields = %{"task_id" => task.id, "tag_id" => tag.id}

      assert [%{status: "rejected", reason: "invalid_id"}] =
               Push.push(user, [insert("task_tag", uuid(), fields)])

      link = Link.id(:task, task.id, tag.id)
      assert [%{status: "applied"}] = Push.push(user, [insert("task_tag", link, fields)])

      assert [%{status: "applied"}] =
               Push.push(user, [patch("task_tag", link, %{"discarded_at" => now()})])

      assert Sync.pull(user, nil).rows["task_tag"] == []

      assert [%{status: "applied"}] =
               Push.push(user, [patch("task_tag", link, %{"discarded_at" => nil})])

      assert [_] = Sync.pull(user, nil).rows["task_tag"]
    end
  end

  # ADR 0014's acceptance scenario: offline, the phone checks one item off
  # and adds another while the laptop renames a third.
  test "two devices' edits all survive", %{user: user} do
    {:ok, milk} = Tasks.create_task(user, %{title: "Milk"}, uuid())
    {:ok, eggs} = Tasks.create_task(user, %{title: "Eggs"}, uuid())
    cursor = Sync.pull(user, nil).cursor

    {:ok, _} = Tasks.rename_task(user, eggs.id, "Free-range eggs", uuid())

    bread = uuid()

    assert [%{status: "applied"}, %{status: "applied"}] =
             Push.push(user, [
               patch("task", milk.id, %{"state" => "done"}),
               insert("task", bread, %{"title" => "Bread"})
             ])

    rows = Sync.pull(user, cursor).rows["task"] |> Map.new(&{&1["id"], &1})
    assert rows[milk.id]["state"] == "done"
    assert rows[eggs.id]["title"] == "Free-range eggs"
    assert rows[bread]["title"] == "Bread"
  end

  defp insert(entity, id, fields),
    do: %{
      "id" => uuid(),
      "entity" => entity,
      "entity_id" => id,
      "op" => "insert",
      "fields" => fields
    }

  defp patch(entity, id, fields, at \\ nil),
    do: %{
      "id" => uuid(),
      "entity" => entity,
      "entity_id" => id,
      "op" => "patch",
      "fields" => fields,
      "at" => at
    }

  defp now, do: DateTime.utc_now(:second) |> DateTime.to_iso8601()
  defp uuid, do: Ecto.UUID.generate(version: 7)
end
