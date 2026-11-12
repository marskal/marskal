defmodule Marskal.ReviewTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.Dates
  alias Marskal.ProjectFolders
  alias Marskal.ProjectNav
  alias Marskal.Projects
  alias Marskal.Review
  alias Marskal.Tags
  alias Marskal.Tasks

  setup do
    user = AccountsFixtures.user_fixture()
    %{user: user, today: Dates.today("Europe/Copenhagen")}
  end

  test "lists To-Do projects due by day, then in sidebar order", %{user: user, today: today} do
    {:ok, folder} = ProjectFolders.create_folder(user, %{"name" => "Work"}, command())
    b = due!(user, "B", today, %{project_folder_id: folder.id})
    a = due!(user, "A", today)
    older = due!(user, "Older", Date.add(today, -3))
    _later = due!(user, "Later", Date.add(today, 1))
    done = due!(user, "Done", today)
    {:ok, _} = Projects.complete_project(user, done.id, command())

    {:ok, never} =
      Projects.create_project(user, %{title: "Never", review_interval: nil}, command())

    # Sidebar order: the folder came first, so B (in it) before A.
    assert titles(Review.due(user)) == ["Older", "B", "A"]
    assert Review.count(user) == 3
    assert [%{folder: %{name: "Work"}}] = Enum.filter(Review.due(user), &(&1.project.id == b.id))

    assert Review.next(user, older.id).id == b.id
    assert Review.due?(user, a)
    refute Review.due?(user, never)

    assert ProjectNav.build(user).review_due == 3
    assert Review.count(AccountsFixtures.user_fixture()) == 0
  end

  test "deferred projects and those in a dropped folder are listed", %{user: user, today: today} do
    {:ok, folder} = ProjectFolders.create_folder(user, %{"name" => "Old"}, command())
    {:ok, _} = ProjectFolders.update_folder(user, folder.id, %{"state" => "dropped"}, command())

    due!(user, "Paused", today, %{deferred_indefinitely: true})
    due!(user, "Filed", today, %{project_folder_id: folder.id})

    rows = Review.due(user)
    assert Enum.sort(titles(rows)) == ["Filed", "Paused"]
    assert %{deferred?: true, stalled?: false} = Enum.find(rows, &(&1.project.title == "Paused"))
  end

  test "a project with no available task is stalled", %{user: user, today: today} do
    empty = due!(user, "Empty", today)
    busy = due!(user, "Busy", today)
    held = due!(user, "Held", today)
    {:ok, _} = Tasks.create_task(user, %{title: "Call", project_id: busy.id}, command())

    {:ok, task} = Tasks.create_task(user, %{title: "Wait", project_id: held.id}, command())
    {:ok, waiting} = Tags.create_tag(user, %{"name" => "Waiting"}, command())
    {:ok, _} = Tags.update_tag(user, waiting.id, %{"state" => "on_hold"}, command())
    {:ok, _} = Tags.tag_task(user, task.id, waiting.id, command())

    stalled = Map.new(Review.due(user), &{&1.project.id, &1.stalled?})
    assert stalled == %{empty.id => true, busy.id => false, held.id => true}
  end

  test "marking reviewed takes it off the list", %{user: user, today: today} do
    project = due!(user, "Garden", today)
    {:ok, _} = Projects.mark_reviewed(user, project.id, command())
    assert Review.due(user) == []
  end

  defp due!(user, title, day, attrs \\ %{}) do
    {:ok, project} = Projects.create_project(user, Map.put(attrs, :title, title), command())
    {:ok, project} = Projects.update_project(user, project.id, %{next_review_on: day}, command())
    project
  end

  defp titles(rows), do: Enum.map(rows, & &1.project.title)
  defp command, do: Ecto.UUID.generate(version: 7)
end
