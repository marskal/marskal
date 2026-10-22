defmodule Marskal.FlaggedTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.Projects
  alias Marskal.Tasks

  setup do
    %{user: AccountsFixtures.user_fixture()}
  end

  test "the Flagged view has open tasks flagged by themselves or by their project", %{
    user: user
  } do
    {:ok, home} = Projects.create_project(user, %{title: "Home", flagged: true}, command())
    {:ok, work} = Projects.create_project(user, %{title: "Work"}, command())

    {:ok, paint} = Tasks.create_task(user, %{title: "Paint", project_id: home.id}, command())

    {:ok, call} =
      Tasks.create_task(user, %{title: "Call", project_id: work.id, flagged: true}, command())

    {:ok, _} = Tasks.create_task(user, %{title: "Mail", project_id: work.id}, command())
    {:ok, milk} = Tasks.create_task(user, %{title: "Milk", flagged: true}, command())

    {:ok, _} =
      Tasks.create_task(user, %{title: "Sub", parent_id: call.id, project_id: work.id}, command())

    {:ok, done} = Tasks.create_task(user, %{title: "Done", flagged: true}, command())
    {:ok, _} = Tasks.complete_task(user, done.id, command())

    {:ok, later} =
      Tasks.create_task(
        user,
        %{title: "Later", flagged: true, deferred_indefinitely: true},
        command()
      )

    assert titles(Tasks.list_flagged(user)) == ["Paint", "Call", "Milk"]

    assert titles(Tasks.list_flagged(user, show: [:deferred])) == [
             "Paint",
             "Call",
             "Milk",
             "Later"
           ]

    other = AccountsFixtures.user_fixture()
    assert Tasks.list_flagged(other) == []

    tasks =
      Tasks.list_open(user, show: [:deferred]) ++ Tasks.list_inbox(user, show: [:deferred])

    assert Tasks.flagged_ids(user, tasks) ==
             MapSet.new([paint.id, call.id, milk.id, later.id])
  end

  test "a flag is set and cleared as a field, and a nil one is refused", %{user: user} do
    {:ok, task} = Tasks.create_task(user, %{title: "Call"}, command())
    refute task.flagged

    {:ok, task} = Tasks.update_task(user, task.id, %{"flagged" => "true"}, command())
    assert task.flagged

    assert {:error, %Ecto.Changeset{}} =
             Tasks.update_task(user, task.id, %{"flagged" => nil}, command())

    {:ok, project} = Projects.create_project(user, %{title: "Home"}, command())
    {:ok, project} = Projects.update_project(user, project.id, %{flagged: true}, command())
    assert project.flagged
  end

  defp titles(tasks), do: Enum.map(tasks, & &1.title)

  defp command, do: Ecto.UUID.generate(version: 7)
end
