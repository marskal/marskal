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
    id = Ecto.UUID.generate()
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

  test "clarify, complete, and rename touch only their fields", %{user: user} do
    {:ok, task} = Tasks.create_task(user, %{"title" => "Milk"}, command_id())

    assert {:ok, clarified} = Tasks.clarify_task(user, task.id, command_id())
    assert clarified.inbox == false
    assert clarified.state == :to_do
    assert clarified.title == "Milk"

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
    {:ok, _} = Tasks.clarify_task(user, open_task.id, command_id())
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
    assert change.patch == %{"title" => "Oat milk", "inbox" => false}
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

  test "the database refuses a task on someone else's project", %{user: user, other: other} do
    {:ok, project} = Marskal.Projects.create_project(other, %{"title" => "Theirs"}, command_id())
    {:ok, task} = Tasks.create_task(user, %{"title" => "Mine"}, command_id())

    assert {:error, changeset} = Tasks.file_task(user, task.id, project.id, command_id())
    assert "must belong to you" in errors_on(changeset).project_id
    assert Repo.get!(Task, task.id).project_id == nil
  end

  defp command_id, do: Ecto.UUID.generate()

  defp uuid_version(id) do
    <<_::48, version::4, _::76>> = Ecto.UUID.dump!(id)
    version
  end
end
