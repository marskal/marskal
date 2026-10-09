defmodule Marskal.RecurrenceTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.Changes.Change
  alias Marskal.Recurrence
  alias Marskal.Recurrence.Series
  alias Marskal.Sync
  alias Marskal.Sync.Push
  alias Marskal.Tasks
  alias Marskal.Tasks.Task

  @friday ~U[2026-10-09 15:00:00Z]

  setup do
    %{user: AccountsFixtures.user_fixture(), other: AccountsFixtures.user_fixture()}
  end

  describe "series" do
    test "holds a rule", %{user: user} do
      {:ok, series} =
        Recurrence.create_series(
          user,
          %{
            kind: :task,
            mode: :regular,
            anchor: :due,
            interval: 2,
            frequency: :weeks,
            weekdays: [5, 2, 2]
          },
          command()
        )

      assert %Series{kind: :task, interval: 2, weekdays: [2, 5], stopped_at: nil} =
               Recurrence.get_series(user, series.id)
    end

    test "takes the user's week start unless it is given one", %{user: user} do
      {:ok, _} = Marskal.Accounts.update_preferences(user, %{week_start: 7}, command())
      rule = %{kind: :task, mode: :regular, anchor: :due, interval: 2, frequency: :weeks}

      {:ok, series} = Recurrence.create_series(user, rule, command())
      assert series.week_start == 7

      {:ok, series} = Recurrence.create_series(user, Map.put(rule, :week_start, 1), command())
      assert series.week_start == 1

      {:ok, _} = Marskal.Accounts.update_preferences(user, %{week_start: 6}, command())
      assert Recurrence.get_series(user, series.id).week_start == 1

      assert {:error, changeset} =
               Recurrence.create_series(user, Map.put(rule, :week_start, 8), command())

      assert "is invalid" in errors_on(changeset).week_start
    end

    test "rejects a rule that does not fit together", %{user: user} do
      base = %{kind: :task, mode: :regular, anchor: :due, interval: 1, frequency: :days}

      for {attrs, field} <- [
            {%{interval: 0}, :interval},
            {%{end_count: 0}, :end_count},
            {%{weekdays: [1]}, :weekdays},
            {%{frequency: :weeks, weekdays: [8]}, :weekdays},
            {%{on_days: ["1:day"]}, :on_days},
            {%{frequency: :months, on_days: ["32:day"]}, :on_days},
            {%{frequency: :months, on_days: ["6:friday"]}, :on_days},
            {%{frequency: :months, on_days: ["-6:friday"]}, :on_days},
            {%{frequency: :months, on_days: ["1:payday"]}, :on_days},
            {%{frequency: :months, on_days: ["10:14:day"]}, :on_days},
            {%{frequency: :years, on_days: ["14:day"]}, :on_days},
            {%{frequency: :years, on_days: ["13:14:day"]}, :on_days},
            {%{mode: :on_completion, frequency: :weeks, weekdays: [1]}, :weekdays},
            {%{mode: :on_completion, frequency: :months, on_days: ["15:day"]}, :on_days},
            {%{mode: nil}, :mode},
            {%{kind: :project}, :kind}
          ] do
        assert {:error, changeset} =
                 Recurrence.create_series(user, Map.merge(base, attrs), command())

        assert Map.has_key?(errors_on(changeset), field), inspect(attrs)
      end
    end

    test "keeps month and year days as rows, in calendar order", %{user: user} do
      rule = %{kind: :task, mode: :regular, anchor: :planned, interval: 1}

      assert {:ok, %Series{on_days: ["15:day", "-1:day", "2:tuesday", "-1:work_day"]}} =
               Recurrence.create_series(
                 user,
                 Map.merge(rule, %{
                   frequency: :months,
                   on_days: ["-1:work_day", "-1:day", "2:tuesday", "15:day", "15:day"]
                 }),
                 command()
               )

      assert {:ok, %Series{on_days: ["4:14:day", "10:14:day", "10:-1:monday"]}} =
               Recurrence.create_series(
                 user,
                 Map.merge(rule, %{
                   frequency: :years,
                   on_days: ["10:-1:monday", "10:14:day", "4:14:day"]
                 }),
                 command()
               )
    end

    test "the database refuses a day row that does not parse", %{user: user} do
      changeset =
        user
        |> series_fixture()
        |> Ecto.Changeset.change(frequency: :months, on_days: ["32:day"])
        |> Ecto.Changeset.check_constraint(:on_days, name: :recurrence_series_on_days)

      assert {:error, changeset} = Repo.update(changeset)
      assert "is invalid" in errors_on(changeset).on_days
    end

    test "rows counted from the end are kept, and sorted after the rest", %{user: user} do
      assert {:ok, %Series{on_days: ["15:day", "-2:day", "-1:day", "-5:work_day"]} = series} =
               Recurrence.create_series(
                 user,
                 %{
                   kind: :task,
                   mode: :regular,
                   anchor: :due,
                   interval: 1,
                   frequency: :months,
                   on_days: ["-5:work_day", "-1:day", "-2:day", "15:day"]
                 },
                 command()
               )

      assert {:ok, _} =
               Repo.update(Ecto.Changeset.change(series, on_days: ["-5:day", "-2:friday"]))
    end

    test "a rule change patches the whole rule", %{user: user} do
      series = series_fixture(user)
      {:ok, _} = Recurrence.update_series(user, series.id, %{interval: 3}, command())

      assert %{"interval" => 3, "frequency" => "weeks", "mode" => "regular", "weekdays" => []} =
               last_patch(user)
    end

    test "stopping patches only stopped_at", %{user: user} do
      series = series_fixture(user)
      {:ok, _} = Recurrence.stop_series(user, series.id, command())

      assert [_] = Map.keys(last_patch(user))
      assert %Series{stopped_at: %DateTime{}} = Recurrence.get_series(user, series.id)
    end

    test "is the owner's only", %{user: user, other: other} do
      series = series_fixture(user)
      assert Recurrence.get_series(other, series.id) == nil

      assert {:error, :not_found} =
               Recurrence.update_series(other, series.id, %{interval: 2}, command())
    end
  end

  describe "occurrences" do
    test "a new task joins a series at its anchor date", %{user: user} do
      series = series_fixture(user)

      {:ok, task} =
        Tasks.create_task(
          user,
          %{title: "Trash", due_at: @friday, series_id: series.id, occurrence_for: @friday},
          command()
        )

      assert %Task{series_id: id, occurrence_for: @friday} = task
      assert id == series.id
    end

    test "an existing task joins, once", %{user: user} do
      series = series_fixture(user)
      {:ok, task} = Tasks.create_task(user, %{title: "Trash", due_at: @friday}, command())

      join = %{series_id: series.id, occurrence_for: @friday}

      assert {:ok, %Task{occurrence_for: @friday}} =
               Tasks.update_task(user, task.id, join, command())

      other = series_fixture(user)

      assert {:error, changeset} =
               Tasks.update_task(user, task.id, %{series_id: other.id}, command())

      assert %{series_id: ["cannot change once set"]} = errors_on(changeset)
    end

    test "keeps its slot when its date moves", %{user: user} do
      series = series_fixture(user)
      task = occurrence_fixture(user, series)

      {:ok, moved} =
        Tasks.update_task(user, task.id, %{due_at: ~U[2026-10-10 15:00:00Z]}, command())

      assert moved.occurrence_for == @friday

      assert {:error, changeset} =
               Tasks.update_task(user, task.id, %{occurrence_for: moved.due_at}, command())

      assert %{series_id: ["cannot change once set"]} = errors_on(changeset)
    end

    test "the database keeps the slot too", %{user: user} do
      task = occurrence_fixture(user, series_fixture(user))

      assert_raise Postgrex.Error, ~r/already occurrence/, fn ->
        Repo.update_all(from(t in Task, where: t.id == ^task.id),
          set: [occurrence_for: ~U[2026-10-10 15:00:00Z]]
        )
      end
    end

    test "must name the anchor date and come with series_id", %{user: user} do
      series = series_fixture(user)

      for {attrs, field, message} <- [
            {%{due_at: @friday, series_id: series.id, occurrence_for: ~U[2026-10-10 15:00:00Z]},
             :occurrence_for, "must be the due date"},
            {%{series_id: series.id, occurrence_for: @friday}, :occurrence_for,
             "must be the due date"},
            {%{due_at: @friday, series_id: series.id}, :occurrence_for, "comes with series_id"},
            {%{due_at: @friday, occurrence_for: @friday}, :occurrence_for, "comes with series_id"}
          ] do
        assert {:error, changeset} =
                 Tasks.create_task(user, Map.put(attrs, :title, "Trash"), command())

        assert message in Map.get(errors_on(changeset), field, []), inspect(attrs)
      end
    end

    test "a client joins only a series' first occurrence", %{user: user} do
      series = series_fixture(user)
      first = occurrence_fixture(user, series)
      # Discarded, as a deleted earlier occurrence is; deleting the latest
      # would end the series.
      Repo.update_all(from(t in Task, where: t.id == ^first.id), set: [discarded_at: @friday])
      next = ~U[2026-10-16 15:00:00Z]

      assert {:error, changeset} =
               Tasks.create_task(
                 user,
                 %{title: "Again", due_at: next, series_id: series.id, occurrence_for: next},
                 command()
               )

      assert %{series_id: ["already has its first occurrence"]} = errors_on(changeset)
    end

    test "the database holds one row per slot", %{user: user} do
      series = series_fixture(user)
      occurrence_fixture(user, series)
      {:ok, other} = Tasks.create_task(user, %{title: "Again", due_at: @friday}, command())

      assert_raise Postgrex.Error, ~r/tasks_series_id_occurrence_for_key/, fn ->
        Repo.update_all(from(t in Task, where: t.id == ^other.id),
          set: [series_id: series.id, occurrence_for: @friday]
        )
      end
    end

    test "not in a stopped, deleted, or someone else's series", %{user: user, other: other} do
      stopped = series_fixture(user)
      {:ok, _} = Recurrence.stop_series(user, stopped.id, command())
      deleted = series_fixture(user)
      {:ok, _} = Recurrence.delete_series(user, deleted.id, command())
      theirs = series_fixture(other)

      for {series, message} <- [
            {stopped, "has stopped"},
            {deleted, "must be one of your series"},
            {theirs, "must be one of your series"}
          ] do
        assert {:error, changeset} =
                 Tasks.create_task(
                   user,
                   %{
                     title: "Trash",
                     due_at: @friday,
                     series_id: series.id,
                     occurrence_for: @friday
                   },
                   command()
                 )

        assert %{series_id: [^message]} = errors_on(changeset)
      end
    end

    test "stay when the series is deleted", %{user: user} do
      series = series_fixture(user)
      task = occurrence_fixture(user, series)
      {:ok, _} = Recurrence.delete_series(user, series.id, command())

      assert %Task{series_id: id, occurrence_for: @friday} = Tasks.get_task(user, task.id)
      assert id == series.id
    end
  end

  describe "repeat_task/4" do
    test "makes a series with the task as its first occurrence", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{title: "Trash", due_at: @friday}, command())
      rule = %{"mode" => "regular", "anchor" => "due", "interval" => 1, "frequency" => "weeks"}

      {:ok, series} = Recurrence.repeat_task(user, task.id, rule, command())

      assert %Series{kind: :task, frequency: :weeks} = series
      assert %Task{occurrence_for: @friday} = joined = Tasks.get_task(user, task.id)
      assert joined.series_id == series.id
      assert Recurrence.repeating_ids(user, [joined]) == MapSet.new([task.id])

      assert {:error, :already_repeating} =
               Recurrence.repeat_task(user, task.id, rule, command())

      {:ok, _} = Recurrence.stop_series(user, series.id, command())
      assert Recurrence.repeating_ids(user, [joined]) == MapSet.new()
    end

    test "needs the anchor date, and leaves nothing behind without it", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{title: "Trash", due_at: @friday}, command())
      rule = %{mode: :regular, anchor: :planned, interval: 1, frequency: :weeks}

      assert {:error, changeset} = Recurrence.repeat_task(user, task.id, rule, command())
      assert "needs the task's Planned date" in errors_on(changeset).anchor
      assert Repo.aggregate(Series, :count) == 0
      assert Tasks.get_task(user, task.id).series_id == nil
    end
  end

  describe "occurrence_id/2" do
    test "is v5 of the series and the instant, with six fractional digits" do
      series_id = "0192F0A0-0000-7000-8000-000000000001"

      assert Recurrence.occurrence_id(series_id, @friday) ==
               Marskal.Uuid.v5(
                 "a5c0ffee-0014-5000-8000-000000000014",
                 "0192f0a0-0000-7000-8000-000000000001|2026-10-09T15:00:00.000000Z"
               )

      in_copenhagen = DateTime.shift_zone!(@friday, "Europe/Copenhagen")

      assert Recurrence.occurrence_id(series_id, in_copenhagen) ==
               Recurrence.occurrence_id(series_id, @friday)
    end
  end

  describe "sync" do
    test "a client creates, edits, and deletes a series", %{user: user} do
      id = Ecto.UUID.generate()

      rule = %{
        "kind" => "task",
        "mode" => "on_completion",
        "anchor" => "defer",
        "interval" => 3,
        "frequency" => "days"
      }

      assert [%{status: "applied"}, %{status: "applied"}, %{status: "applied"}] =
               Push.push(user, [
                 command("recurrence_series", id, "insert", rule),
                 command("recurrence_series", id, "patch", %{"interval" => 4}),
                 command("recurrence_series", id, "patch", %{"stopped_at" => now()})
               ])

      assert %{
               "interval" => 4,
               "mode" => "on_completion",
               "weekdays" => [],
               "stopped_at" => stopped
             } =
               hd(Sync.pull(user, nil).rows["recurrence_series"])

      assert stopped

      assert [%{status: "applied"}] =
               Push.push(user, [
                 command("recurrence_series", id, "patch", %{"discarded_at" => now()})
               ])

      assert Sync.pull(user, nil).rows["recurrence_series"] == []
    end

    test "a client may not set the kind after insert", %{user: user} do
      series = series_fixture(user)

      assert [%{status: "rejected", reason: "field_not_allowed"}] =
               Push.push(user, [
                 command("recurrence_series", series.id, "patch", %{"kind" => "project"})
               ])
    end

    test "a task joins a series, and its pull row says so", %{user: user} do
      series = series_fixture(user)
      id = Recurrence.occurrence_id(series.id, @friday)
      at = DateTime.to_iso8601(@friday)

      assert [%{status: "applied"}] =
               Push.push(user, [
                 command("task", id, "insert", %{
                   "title" => "Trash",
                   "due_at" => at,
                   "series_id" => series.id,
                   "occurrence_for" => at
                 })
               ])

      series_id = series.id

      assert [%{"id" => ^id, "series_id" => ^series_id, "occurrence_for" => ^at}] =
               Sync.pull(user, nil).rows["task"]
    end

    test "projects carry the occurrence fields, read-only for now", %{user: user} do
      {:ok, project} = Marskal.Projects.create_project(user, %{title: "Review"}, command())

      assert [%{"series_id" => nil, "occurrence_for" => nil}] =
               Sync.pull(user, nil).rows["project"]

      assert [%{status: "rejected", reason: "field_not_allowed"}] =
               Push.push(user, [
                 command("project", project.id, "patch", %{"series_id" => Ecto.UUID.generate()})
               ])
    end

    test "a patch that moves a task's slot is rejected", %{user: user} do
      task = occurrence_fixture(user, series_fixture(user))

      assert [%{status: "rejected", reason: "invalid"}] =
               Push.push(user, [
                 command("task", task.id, "patch", %{"occurrence_for" => "2026-10-10T15:00:00Z"})
               ])
    end
  end

  defp series_fixture(user) do
    {:ok, series} =
      Recurrence.create_series(
        user,
        %{kind: :task, mode: :regular, anchor: :due, interval: 1, frequency: :weeks},
        command()
      )

    series
  end

  defp occurrence_fixture(user, series) do
    {:ok, task} =
      Tasks.create_task(
        user,
        %{title: "Trash", due_at: @friday, series_id: series.id, occurrence_for: @friday},
        command()
      )

    task
  end

  defp last_patch(user) do
    Repo.one!(
      from c in Change,
        where: c.user_id == ^user.id,
        order_by: [desc: c.id],
        limit: 1,
        select: c.patch
    )
  end

  defp command(entity, id, op, fields),
    do: %{
      "id" => command(),
      "entity" => entity,
      "entity_id" => id,
      "op" => op,
      "fields" => fields
    }

  defp now, do: DateTime.utc_now(:second) |> DateTime.to_iso8601()
  defp command, do: Ecto.UUID.generate()
end
