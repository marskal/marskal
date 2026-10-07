defmodule Marskal.DatesTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.Changes.Change
  alias Marskal.Dates
  alias Marskal.Projects
  alias Marskal.Repo
  alias Marskal.Tasks
  alias MarskalWeb.DateFields

  @zone "Europe/Copenhagen"

  setup do
    %{user: AccountsFixtures.user_fixture(), other: AccountsFixtures.user_fixture()}
  end

  describe "wall clock" do
    test "a day with no time takes the field's default, in the zone" do
      assert Dates.from_local(~D[2026-09-30], nil, :due_at, @zone) == ~U[2026-09-30 15:00:00Z]
      assert Dates.from_local(~D[2026-12-30], nil, :due_at, @zone) == ~U[2026-12-30 16:00:00Z]

      assert Dates.from_local(~D[2026-09-30], nil, :defer_until, @zone) ==
               ~U[2026-09-29 22:00:00Z]
    end

    test "a time skipped by DST moves forward; a repeated one takes the first" do
      assert Dates.from_local(~D[2026-03-29], ~T[02:30:00], :due_at, @zone) ==
               ~U[2026-03-29 01:00:00Z]

      assert Dates.from_local(~D[2026-10-25], ~T[02:30:00], :due_at, @zone) ==
               ~U[2026-10-25 00:30:00Z]
    end

    test "a day's bounds follow the zone, 25 hours on the long day" do
      assert Dates.day_bounds(~D[2026-10-25], @zone) ==
               {~U[2026-10-24 22:00:00Z], ~U[2026-10-25 23:00:00Z]}
    end

    test "imported values: offset, floating, and date only" do
      assert Dates.parse_source("2024-03-01T16:00:00.000Z", :due_at, @zone) ==
               ~U[2024-03-01 16:00:00Z]

      assert Dates.parse_source("2026-09-30T10:00:00", :due_at, @zone) == ~U[2026-09-30 08:00:00Z]
      assert Dates.parse_source("2026-09-30", :planned_at, @zone) == ~U[2026-09-30 07:00:00Z]
      assert Dates.parse_source("next week", :due_at, @zone) == nil
      assert Dates.parse_source(nil, :due_at, @zone) == nil
    end
  end

  describe "defer" do
    test "indefinite clears the until instant, and an instant clears indefinite", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{"title" => "Paint"}, command_id())
      later = ~U[2030-01-01 08:00:00Z]

      {:ok, task} = Tasks.update_task(user, task.id, %{defer_until: later}, command_id())
      assert task.defer_until == later
      refute task.deferred_indefinitely

      {:ok, task} = Tasks.update_task(user, task.id, %{deferred_indefinitely: true}, command_id())
      assert task.deferred_indefinitely
      assert task.defer_until == nil
      assert last_patch() == %{"defer_until" => nil, "deferred_indefinitely" => true}

      {:ok, task} = Tasks.update_task(user, task.id, %{defer_until: later}, command_id())
      refute task.deferred_indefinitely

      assert last_patch() == %{
               "defer_until" => "2030-01-01T08:00:00Z",
               "deferred_indefinitely" => false
             }
    end

    test "both shapes at once are refused", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{"title" => "Paint"}, command_id())

      assert {:error, %Ecto.Changeset{}} =
               Tasks.update_task(
                 user,
                 task.id,
                 %{deferred_indefinitely: true, defer_until: ~U[2030-01-01 08:00:00Z]},
                 command_id()
               )
    end

    test "the open stream hides deferred tasks until the instant passes", %{user: user} do
      now = DateTime.utc_now(:second)

      for {title, attrs} <- [
            {"Later", %{defer_until: DateTime.add(now, 3600)}},
            {"Someday", %{deferred_indefinitely: true}},
            {"Past", %{defer_until: DateTime.add(now, -3600)}},
            {"Plain", %{}}
          ] do
        {:ok, _} =
          Tasks.create_task(user, Map.merge(%{title: title, inbox: false}, attrs), command_id())
      end

      assert titles(Tasks.list_open(user)) == ["Plain", "Past"]

      assert titles(Tasks.list_open(user, unavailable: true)) == [
               "Plain",
               "Past",
               "Someday",
               "Later"
             ]
    end

    test "a task in a deferred project is deferred", %{user: user} do
      {:ok, project} =
        Projects.create_project(
          user,
          %{title: "Garden", deferred_indefinitely: true},
          command_id()
        )

      {:ok, task} = Tasks.create_task(user, %{title: "Dig", project_id: project.id}, command_id())

      assert Tasks.list_open(user) == []
      assert Tasks.deferred_ids(user, [task]) == MapSet.new([task.id])

      {:ok, _} =
        Projects.update_project(user, project.id, %{deferred_indefinitely: false}, command_id())

      assert titles(Tasks.list_open(user)) == ["Dig"]
    end
  end

  describe "resolved_at" do
    test "is set on the first resolve and kept after reopening", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{"title" => "Milk"}, command_id())
      assert task.resolved_at == nil

      {:ok, done} = Tasks.complete_task(user, task.id, command_id())
      assert %DateTime{} = first = done.resolved_at

      {:ok, reopened} = Tasks.reopen_task(user, task.id, command_id())
      assert reopened.resolved_at == first

      Repo.update_all(Marskal.Tasks.Task, set: [resolved_at: ~U[2026-01-01 00:00:00Z]])
      {:ok, dropped} = Tasks.drop_task(user, task.id, command_id())
      assert dropped.resolved_at == ~U[2026-01-01 00:00:00Z]
    end

    test "a task created resolved gets one, from its source if given", %{user: user} do
      {:ok, now} = Tasks.create_task(user, %{"title" => "A", "state" => "done"}, command_id())
      assert %DateTime{} = now.resolved_at

      {:ok, imported} =
        Tasks.create_task(
          user,
          %{"title" => "B", "state" => "done", "resolved_at" => ~U[2024-02-01 00:00:00Z]},
          command_id()
        )

      assert imported.resolved_at == ~U[2024-02-01 00:00:00Z]
    end

    test "a client's time stands inside the skew window, and receipt time outside it" do
      now = ~U[2026-10-02 12:00:00Z]

      assert Dates.resolution_time(~U[2026-10-02 12:02:00Z], now) == ~U[2026-10-02 12:02:00Z]
      assert Dates.resolution_time(~U[2026-10-02 12:02:01Z], now) == now
      assert Dates.resolution_time(~U[2026-09-30 12:00:00Z], now) == ~U[2026-09-30 12:00:00Z]
      assert Dates.resolution_time(~U[2026-09-30 11:59:59Z], now) == now

      assert Dates.resolution_time(~U[2026-10-02 11:00:00.750000Z], now) ==
               ~U[2026-10-02 11:00:00Z]

      assert Dates.resolution_time(nil, now) == now
    end

    test "a resolve from a client takes its time, clamped", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{"title" => "Milk"}, command_id())
      an_hour_ago = DateTime.add(DateTime.utc_now(:second), -3600)

      {:ok, done} =
        Tasks.update_task(user, task.id, %{state: :done}, command_id(), at: an_hour_ago)

      assert done.resolved_at == an_hour_ago

      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command_id())
      next_week = DateTime.add(DateTime.utc_now(), 7, :day)

      {:ok, dropped} =
        Projects.update_project(user, project.id, %{state: :dropped}, command_id(), at: next_week)

      assert DateTime.diff(DateTime.utc_now(), dropped.resolved_at) in 0..5
    end

    test "projects follow the same rule", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command_id())
      {:ok, done} = Projects.complete_project(user, project.id, command_id())
      assert %DateTime{} = done.resolved_at
    end
  end

  describe "discard" do
    test "a deleted task leaves every read, and later patches are ignored", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{title: "Oops", inbox: false}, command_id())
      delete = command_id()

      {:ok, discarded} = Tasks.delete_task(user, task.id, delete)
      assert %DateTime{} = discarded.discarded_at

      assert Tasks.get_task(user, task.id) == nil
      assert Tasks.list_open(user) == []
      assert Tasks.get_tasks(user, [task.id]) == []
      assert {:error, :not_found} = Tasks.rename_task(user, task.id, "Back", command_id())
      assert {:error, :not_found} = Tasks.delete_task(user, task.id, command_id())

      # Replaying the delete is a no-op that still succeeds.
      changes = Repo.aggregate(Change, :count)
      assert {:ok, _} = Tasks.delete_task(user, task.id, delete)
      assert Repo.aggregate(Change, :count) == changes
    end

    test "deleting a project discards its tasks, one change each", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command_id())

      for title <- ["Dig", "Plant"] do
        {:ok, _} = Tasks.create_task(user, %{title: title, project_id: project.id}, command_id())
      end

      changes = Repo.aggregate(Change, :count)
      delete = command_id()
      {:ok, _} = Projects.delete_project(user, project.id, delete)

      assert Projects.get_project(user, project.id) == nil
      assert Projects.list_open(user) == []
      assert Tasks.list_project_tasks(user, project.id) == []
      assert Repo.aggregate(Change, :count) == changes + 3

      assert {:ok, _} = Projects.delete_project(user, project.id, delete)
      assert Repo.aggregate(Change, :count) == changes + 3
    end

    test "someone else's task cannot be deleted", %{user: user, other: other} do
      {:ok, task} = Tasks.create_task(user, %{title: "Mine"}, command_id())
      assert {:error, :not_found} = Tasks.delete_task(other, task.id, command_id())
      assert Tasks.get_task(user, task.id)
    end
  end

  describe "agenda" do
    test "lists a day's plans in the user's zone, and carries earlier ones", %{
      user: user,
      other: other
    } do
      plan = fn owner, title, at ->
        {:ok, _} = Tasks.create_task(owner, %{title: title, planned_at: at}, command_id())
      end

      # 23:30 on the 29th in Copenhagen is still the 29th, though UTC says 21:30.
      plan.(user, "Late", ~U[2026-09-29 21:30:00Z])
      plan.(user, "Morning", ~U[2026-09-30 07:00:00Z])
      plan.(user, "Midnight", ~U[2026-09-29 22:00:00Z])
      plan.(user, "Next day", ~U[2026-10-01 07:00:00Z])
      plan.(other, "Not mine", ~U[2026-09-30 07:00:00Z])

      assert titles(Tasks.list_planned(user, ~D[2026-09-30])) == ["Midnight", "Morning"]

      assert titles(Tasks.list_planned(user, ~D[2026-09-30], carry_over: true)) ==
               ["Late", "Midnight", "Morning"]
    end

    test "leaves out done and deferred plans", %{user: user} do
      at = DateTime.utc_now(:second)
      {:ok, done} = Tasks.create_task(user, %{title: "Done", planned_at: at}, command_id())
      {:ok, _} = Tasks.complete_task(user, done.id, command_id())

      {:ok, _} =
        Tasks.create_task(
          user,
          %{title: "Deferred", planned_at: at, deferred_indefinitely: true},
          command_id()
        )

      today = Dates.today(Marskal.Accounts.timezone(user))
      assert Tasks.list_planned(user, today) == []
      assert titles(Tasks.list_planned(user, today, unavailable: true)) == ["Deferred"]
    end
  end

  describe "form params" do
    test "an untouched field keeps its stored value, seconds included" do
      record = %{
        defer_until: nil,
        deferred_indefinitely: false,
        planned_at: ~U[2026-09-30 07:00:42Z],
        due_at: ~U[2026-09-30 15:00:00Z]
      }

      params = %{
        "deferred_indefinitely" => ["false"],
        "defer_date" => "",
        "planned_date" => "2026-09-30",
        "planned_time" => "09:00",
        "due_date" => "2026-10-02",
        "due_time" => ""
      }

      assert DateFields.params_to_attrs(params, record, @zone) == %{
               "defer_until" => nil,
               "deferred_indefinitely" => false,
               "planned_at" => ~U[2026-09-30 07:00:42Z],
               "due_at" => ~U[2026-10-02 15:00:00Z]
             }
    end

    test "defer indefinitely leaves the until field out" do
      record = %{defer_until: nil, deferred_indefinitely: false, planned_at: nil, due_at: nil}
      params = %{"deferred_indefinitely" => ["false", "true"], "due_date" => ""}

      assert DateFields.params_to_attrs(params, record, @zone) == %{
               "deferred_indefinitely" => true,
               "planned_at" => nil,
               "due_at" => nil
             }
    end

    test "row labels are relative and show a time only when it is not the default" do
      today = ~D[2026-09-28]
      assert DateFields.short(~U[2026-09-28 15:00:00Z], :due_at, @zone, today) == "Today"
      assert DateFields.short(~U[2026-09-29 08:30:00Z], :due_at, @zone, today) == "Tomorrow 10:30"
      assert DateFields.short(~U[2026-10-02 15:00:00Z], :due_at, @zone, today) == "Fri"
      assert DateFields.short(~U[2026-11-20 16:00:00Z], :due_at, @zone, today) == "20 Nov"
      assert DateFields.short(~U[2027-01-05 16:00:00Z], :due_at, @zone, today) == "5 Jan 2027"
    end
  end

  defp titles(tasks), do: Enum.map(tasks, & &1.title)

  defp last_patch do
    Change |> order_by(desc: :id) |> limit(1) |> Repo.one!() |> Map.fetch!(:patch)
  end

  defp command_id, do: Ecto.UUID.generate()
end
