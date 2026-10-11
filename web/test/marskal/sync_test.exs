defmodule Marskal.SyncTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.ProjectFolders
  alias Marskal.Projects
  alias Marskal.Sync
  alias Marskal.Tags
  alias Marskal.Tasks

  setup do
    %{user: AccountsFixtures.user_fixture(), other: AccountsFixtures.user_fixture()}
  end

  describe "snapshot" do
    test "every live row the user owns, and the latest cursor", %{user: user, other: other} do
      {:ok, folder} = ProjectFolders.create_folder(user, %{name: "Home"}, command())

      {:ok, project} =
        Projects.create_project(
          user,
          %{title: "Garden", project_folder_id: folder.id},
          command()
        )

      {:ok, task} =
        Tasks.create_task(user, %{title: "Dig", project_id: project.id, inbox: false}, command())

      {:ok, tag} = Tags.create_tag(user, %{name: "Outside"}, command())
      {:ok, _} = Tags.tag_task(user, task.id, tag.id, command())
      {:ok, _} = Tags.tag_project(user, project.id, tag.id, command())

      {:ok, gone} = Tasks.create_task(user, %{title: "Oops"}, command())
      {:ok, _} = Tasks.delete_task(user, gone.id, command())
      {:ok, _} = Tasks.create_task(other, %{title: "Not mine"}, command())

      pull = Sync.pull(user, nil)

      assert pull.snapshot
      refute pull.more
      assert pull.user == %{id: user.id, timezone: "Europe/Copenhagen"}
      assert pull.cursor == max_cursor(user)

      assert [%{"id" => id, "title" => "Dig", "project_id" => project_id, "inbox" => false}] =
               pull.rows["task"]

      assert id == task.id and project_id == project.id
      assert [%{"title" => "Garden", "state" => "to_do"}] = pull.rows["project"]
      assert [%{"name" => "Home"}] = pull.rows["project_folder"]
      assert [%{"name" => "Outside"}] = pull.rows["tag"]
      assert [%{"task_id" => ^id}] = pull.rows["task_tag"]
      assert [_] = pull.rows["project_tag"]
    end

    test "leaves out derived fields and the owner", %{user: user} do
      {:ok, parent} = ProjectFolders.create_folder(user, %{name: "Work"}, command())

      {:ok, _} =
        ProjectFolders.create_folder(user, %{name: "Client", parent_id: parent.id}, command())

      for row <- Sync.pull(user, nil).rows["project_folder"] do
        refute Map.has_key?(row, "parent_path")
        refute Map.has_key?(row, "user_id")
      end
    end

    test "carries the URL of tasks and projects", %{user: user} do
      {:ok, _} =
        Tasks.create_task(user, %{title: "Fix", url: "https://jira.example/X-1"}, command())

      {:ok, _} =
        Projects.create_project(user, %{title: "Site", url: "file:///srv/site"}, command())

      rows = Sync.pull(user, nil).rows
      assert [%{"url" => "https://jira.example/X-1"}] = rows["task"]
      assert [%{"url" => "file:///srv/site"}] = rows["project"]
    end

    test "values are encoded as the feed encodes them", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{title: "Call"}, command())
      {:ok, _} = Tasks.complete_task(user, task.id, command())

      [row] = Sync.pull(user, nil).rows["task"]
      assert row["state"] == "done"
      assert {:ok, _, 0} = DateTime.from_iso8601(row["resolved_at"])
    end

    test "holds only the preferences, with cursor 0, for a new user", %{user: user} do
      pull = Sync.pull(user, nil)
      assert pull.cursor == 0
      {[preferences], rest} = Map.pop(pull.rows, "user_preferences")
      assert preferences["id"] == user.id
      assert Enum.all?(rest, fn {_type, rows} -> rows == [] end)
      assert Map.keys(pull.rows) |> Enum.sort() == Enum.sort(Sync.entity_types())
    end
  end

  describe "after a cursor" do
    test "the current row of each changed entity, tombstones included", %{user: user} do
      {:ok, keep} = Tasks.create_task(user, %{title: "Keep"}, command())
      {:ok, drop} = Tasks.create_task(user, %{title: "Drop"}, command())
      cursor = Sync.pull(user, nil).cursor

      {:ok, _} = Tasks.rename_task(user, keep.id, "Kept", command())
      {:ok, _} = Tasks.rename_task(user, keep.id, "Kept!", command())
      {:ok, _} = Tasks.delete_task(user, drop.id, command())

      pull = Sync.pull(user, cursor)
      refute pull.snapshot
      assert pull.cursor == max_cursor(user)

      by_id = Map.new(pull.rows["task"], &{&1["id"], &1})
      assert map_size(by_id) == 2
      assert by_id[keep.id]["title"] == "Kept!"
      assert by_id[drop.id]["discarded_at"]

      assert Sync.pull(user, pull.cursor).rows["task"] == []
      assert Sync.pull(user, pull.cursor).cursor == pull.cursor
    end

    test "pages, with more until the feed is drained", %{user: user} do
      for title <- ~w(a b c d e) do
        {:ok, _} = Tasks.create_task(user, %{title: title}, command())
      end

      first = Sync.pull(user, 0, 2)
      assert first.more
      assert Enum.count(first.rows["task"]) == 2

      second = Sync.pull(user, first.cursor, 2)
      third = Sync.pull(user, second.cursor, 2)
      refute third.more

      titles =
        Enum.flat_map([first, second, third], & &1.rows["task"]) |> Enum.map(& &1["title"])

      assert titles == ~w(a b c d e)
    end

    test "never another user's changes", %{user: user, other: other} do
      {:ok, _} = Tasks.create_task(other, %{title: "Theirs"}, command())
      pull = Sync.pull(user, 0)
      assert pull.rows["task"] == []
      assert pull.cursor == 0
    end
  end

  defp max_cursor(user) do
    Repo.one(from c in Marskal.Changes.Change, where: c.user_id == ^user.id, select: max(c.id))
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
