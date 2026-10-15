defmodule Marskal.TasksTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.Changes.Change
  alias Marskal.Repo
  alias Marskal.Tasks
  alias Marskal.Tasks.Task

  setup do
    user = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()
    %{user: user, other: other}
  end

  test "create mints a uuidv7 when the caller omits the id", %{user: user} do
    {:ok, task} = Tasks.create_task(user, %{"title" => "Milk"}, command_id())

    assert task.title == "Milk"
    assert task.inbox
    assert task.state == :to_do
    assert uuid_version(task.id) == 7
    assert Repo.aggregate(Change, :count) == 1
  end

  test "create keeps a client-supplied id", %{user: user} do
    id = Ecto.UUID.generate(version: 7)
    {:ok, task} = Tasks.create_task(user, %{"id" => id, "title" => "Bread"}, command_id())

    assert task.id == id
  end

  test "replaying a command does not apply it twice", %{user: user} do
    command_id = command_id()
    attrs = %{"title" => "Eggs"}

    assert {:ok, first} = Tasks.create_task(user, attrs, command_id)
    assert {:ok, second} = Tasks.create_task(user, %{"title" => "Other"}, command_id)

    assert first.id == second.id
    assert Repo.aggregate(Task, :count) == 1
    assert Repo.aggregate(Change, :count) == 1
  end

  test "move, complete, and rename touch only their fields", %{user: user} do
    {:ok, task} = Tasks.create_task(user, %{"title" => "Milk"}, command_id())

    assert {:ok, moved} = Tasks.move_task(user, task.id, :none, command_id())
    assert moved.inbox == false
    assert moved.state == :to_do
    assert moved.title == "Milk"

    assert {:ok, renamed} = Tasks.rename_task(user, task.id, "Oat milk", command_id())
    assert renamed.title == "Oat milk"
    assert renamed.inbox == false
    assert renamed.state == :to_do

    assert {:ok, done} = Tasks.complete_task(user, task.id, command_id())
    assert done.state == :done
    assert done.title == "Oat milk"
    assert done.inbox == false
  end

  test "a user cannot update someone else's task", %{user: user, other: other} do
    {:ok, task} = Tasks.create_task(user, %{"title" => "Milk"}, command_id())

    assert {:error, :not_found} = Tasks.drop_task(other, task.id, command_id())
    assert Repo.get!(Task, task.id).state == :to_do
  end

  test "open and inbox lists stay separate", %{user: user} do
    {:ok, inbox_task} = Tasks.create_task(user, %{"title" => "Inbox"}, command_id())
    {:ok, open_task} = Tasks.create_task(user, %{"title" => "Open"}, command_id())
    {:ok, _} = Tasks.move_task(user, open_task.id, :none, command_id())
    {:ok, done} = Tasks.create_task(user, %{"title" => "Done"}, command_id())
    {:ok, _} = Tasks.complete_task(user, done.id, command_id())

    assert Enum.map(Tasks.list_inbox(user), & &1.id) == [inbox_task.id]
    assert Enum.map(Tasks.list_open(user), & &1.id) == [open_task.id]
  end

  test "a command that changes nothing appends nothing and broadcasts nothing", %{user: user} do
    {:ok, task} = Tasks.create_task(user, %{"title" => "Milk"}, command_id())
    Marskal.Changes.subscribe(user)

    assert {:ok, %{state: :done}} = Tasks.complete_task(user, task.id, command_id())
    assert_receive {:marskal_change, "task", id} when id == task.id

    assert {:ok, %{state: :done}} = Tasks.complete_task(user, task.id, command_id())
    refute_receive {:marskal_change, _, _}

    assert Repo.aggregate(Change, :count) == 2
  end

  test "update_task patches several fields in one change row", %{user: user} do
    {:ok, task} = Tasks.create_task(user, %{"title" => "Milk"}, command_id())

    assert {:ok, task} =
             Tasks.update_task(
               user,
               task.id,
               %{"title" => "Oat milk", "notes" => "", "inbox" => "false", "state" => "to_do"},
               command_id()
             )

    assert task.title == "Oat milk"
    refute task.inbox

    change = Repo.one!(from c in Change, order_by: [desc: c.id], limit: 1)
    assert change.user_id == user.id
    assert change.patch == %{"title" => "Oat milk", "inbox" => false, "project_id" => nil}
  end

  describe "location" do
    setup %{user: user} do
      {:ok, project} = Marskal.Projects.create_project(user, %{"title" => "Garden"}, command_id())
      %{project: project}
    end

    test "a new task is in the inbox unless it is given a project", %{
      user: user,
      project: project
    } do
      {:ok, loose} = Tasks.create_task(user, %{"title" => "Loose"}, command_id())

      {:ok, filed} =
        Tasks.create_task(user, %{"title" => "Filed", "project_id" => project.id}, command_id())

      assert Tasks.location(loose) == :inbox
      assert Tasks.location(filed) == project.id
    end

    test "inbox, no project, and a project are one choice", %{user: user, project: project} do
      {:ok, task} = Tasks.create_task(user, %{"title" => "Weed"}, command_id())

      assert {:ok, task} = Tasks.move_task(user, task.id, project.id, command_id())
      assert {task.inbox, task.project_id} == {false, project.id}

      assert {:ok, task} = Tasks.move_task(user, task.id, :inbox, command_id())
      assert {task.inbox, task.project_id} == {true, nil}

      assert {:ok, task} = Tasks.move_task(user, task.id, :none, command_id())
      assert {task.inbox, task.project_id} == {false, nil}
    end

    test "choosing a project on its own leaves the inbox", %{user: user, project: project} do
      {:ok, task} = Tasks.create_task(user, %{"title" => "Weed"}, command_id())

      assert {:ok, task} =
               Tasks.update_task(user, task.id, %{"project_id" => project.id}, command_id())

      refute task.inbox
    end

    test "a move patches both fields together", %{user: user, project: project} do
      {:ok, task} = Tasks.create_task(user, %{"title" => "Weed"}, command_id())
      {:ok, _} = Tasks.move_task(user, task.id, project.id, command_id())

      change = Repo.one!(from c in Change, order_by: [desc: c.id], limit: 1)
      assert change.patch == %{"inbox" => false, "project_id" => project.id}
    end

    test "the inbox and a project together are refused", %{user: user, project: project} do
      {:ok, task} = Tasks.create_task(user, %{"title" => "Weed"}, command_id())

      assert {:error, changeset} =
               Tasks.update_task(
                 user,
                 task.id,
                 %{inbox: true, project_id: project.id},
                 command_id()
               )

      assert "cannot hold a task that has a project" in errors_on(changeset).inbox

      assert_raise Postgrex.Error, ~r/tasks_inbox_no_project/, fn ->
        Repo.query!("UPDATE tasks SET project_id = $1 WHERE id = $2", [
          Ecto.UUID.dump!(project.id),
          Ecto.UUID.dump!(task.id)
        ])
      end
    end
  end

  test "a title or notes over the limit is refused", %{user: user} do
    long_title = String.duplicate("a", Task.title_max() + 1)
    long_notes = String.duplicate("a", Task.notes_max() + 1)

    assert {:error, changeset} = Tasks.create_task(user, %{"title" => long_title}, command_id())
    assert errors_on(changeset).title

    assert {:error, changeset} =
             Tasks.create_task(user, %{"title" => "Milk", "notes" => long_notes}, command_id())

    assert errors_on(changeset).notes

    {:ok, task} = Tasks.create_task(user, %{"title" => "Milk"}, command_id())

    assert {:error, changeset} =
             Tasks.update_task(user, task.id, %{"notes" => long_notes}, command_id())

    assert errors_on(changeset).notes
  end

  test "a task can be created already resolved in one command", %{user: user} do
    {:ok, task} = Tasks.create_task(user, %{"title" => "Old", "state" => "done"}, command_id())

    assert task.state == :done
    assert Repo.aggregate(Change, :count) == 1
  end

  test "an id that is not a uuid finds nothing", %{user: user} do
    assert Tasks.get_task(user, "not-a-uuid") == nil
    assert {:error, :not_found} = Tasks.complete_task(user, "not-a-uuid", command_id())
  end

  test "project task counts follow each live task's own state", %{user: user, other: other} do
    {:ok, project} = Marskal.Projects.create_project(user, %{"title" => "Launch"}, command_id())
    {:ok, elsewhere} = Marskal.Projects.create_project(user, %{"title" => "Other"}, command_id())
    {:ok, _} = Tasks.create_task(user, %{title: "Write", project_id: project.id}, command_id())

    {:ok, parent} =
      Tasks.create_task(user, %{title: "Ship", project_id: project.id}, command_id())

    {:ok, _} =
      Tasks.create_task(
        user,
        %{title: "Announce", project_id: project.id, parent_id: parent.id},
        command_id()
      )

    {:ok, _} = Tasks.complete_task(user, parent.id, command_id())

    {:ok, dropped} =
      Tasks.create_task(user, %{title: "Postpone", project_id: project.id}, command_id())

    {:ok, _} = Tasks.drop_task(user, dropped.id, command_id())

    {:ok, done} =
      Tasks.create_task(user, %{title: "Draft", project_id: project.id}, command_id())

    {:ok, _} = Tasks.complete_task(user, done.id, command_id())

    {:ok, gone} =
      Tasks.create_task(user, %{title: "Scratch", project_id: project.id}, command_id())

    {:ok, _} = Tasks.delete_task(user, gone.id, command_id())

    {:ok, _} =
      Tasks.create_task(user, %{title: "Elsewhere", project_id: elsewhere.id}, command_id())

    {:ok, theirs} = Marskal.Projects.create_project(other, %{"title" => "Theirs"}, command_id())

    {:ok, _} =
      Tasks.create_task(other, %{title: "Secret", project_id: theirs.id}, command_id())

    # The subtask stays To-Do after its parent is done.
    assert Tasks.project_task_counts(user, project.id) == %{
             to_do: 2,
             dropped: 1,
             done: 2,
             total: 5
           }

    assert Tasks.project_task_counts(user, theirs.id) == %{
             to_do: 0,
             dropped: 0,
             done: 0,
             total: 0
           }

    assert Tasks.project_task_counts(user, Ecto.UUID.generate(version: 7)) == %{
             to_do: 0,
             dropped: 0,
             done: 0,
             total: 0
           }
  end

  test "the database refuses a task on someone else's project", %{user: user, other: other} do
    {:ok, project} = Marskal.Projects.create_project(other, %{"title" => "Theirs"}, command_id())
    {:ok, task} = Tasks.create_task(user, %{"title" => "Mine"}, command_id())

    assert {:error, changeset} = Tasks.move_task(user, task.id, project.id, command_id())
    assert "must belong to you" in errors_on(changeset).project_id
    assert Repo.get!(Task, task.id).project_id == nil
  end

  defp command_id, do: Ecto.UUID.generate(version: 7)

  defp uuid_version(id) do
    <<_::48, version::4, _::76>> = Ecto.UUID.dump!(id)
    version
  end
end
