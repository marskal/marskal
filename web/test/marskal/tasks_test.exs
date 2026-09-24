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

  defp command_id, do: Ecto.UUID.generate()

  defp uuid_version(id) do
    <<_::48, version::4, _::76>> = Ecto.UUID.dump!(id)
    version
  end
end
