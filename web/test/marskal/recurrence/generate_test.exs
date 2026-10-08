defmodule Marskal.Recurrence.GenerateTest do
  use Marskal.DataCase, async: true
  use Oban.Testing, repo: Marskal.Repo

  alias Marskal.AccountsFixtures
  alias Marskal.Changes.Change
  alias Marskal.Dates
  alias Marskal.Projects
  alias Marskal.Recurrence
  alias Marskal.Sync
  alias Marskal.Sync.Push
  alias Marskal.Tags
  alias Marskal.Tags.TaskTag
  alias Marskal.Tasks
  alias Marskal.Tasks.Task

  setup do
    %{user: AccountsFixtures.user_fixture()}
  end

  describe "on completion" do
    test "Done creates the next, copied from the one finished", %{user: user} do
      series = series_fixture(user, %{mode: :on_completion, frequency: :days, interval: 3})
      {:ok, project} = Projects.create_project(user, %{title: "Home"}, command())
      {:ok, tag} = Tags.create_tag(user, %{name: "chores"}, command())
      due = hours_ago(5)

      first =
        occurrence_fixture(user, series, due, %{
          notes: "Bins too",
          url: "https://example.com/trash",
          project_id: project.id,
          defer_until: DateTime.add(due, -2, :day)
        })

      {:ok, sibling} =
        Tasks.create_task(user, %{title: "Later", project_id: project.id}, command())

      {:ok, _} = Tags.tag_task(user, first.id, tag.id, command())
      {:ok, done} = Tasks.complete_task(user, first.id, command())

      [next] = later_occurrences(series, first)
      slot = DateTime.add(done.resolved_at, 3, :day)
      assert next.id == Recurrence.occurrence_id(series.id, slot)

      assert %Task{
               title: "Trash",
               notes: "Bins too",
               url: "https://example.com/trash",
               project_id: project_id,
               inbox: false,
               state: :to_do,
               due_at: ^slot,
               occurrence_for: ^slot
             } = next

      assert project_id == project.id
      # Two days before on the zone's calendar, at its own local time.
      {slot_day, _} = Dates.to_local(slot, "Europe/Copenhagen")
      {_, defer_time} = Dates.to_local(first.defer_until, "Europe/Copenhagen")

      assert Dates.to_local(next.defer_until, "Europe/Copenhagen") ==
               {Date.add(slot_day, -2), defer_time}

      assert first.rank < next.rank and next.rank < sibling.rank

      assert Repo.all(from l in TaskTag, where: l.task_id == ^next.id, select: l.tag_id) ==
               [tag.id]
    end

    test "Dropped creates the next too, and To-Do does not", %{user: user} do
      series = series_fixture(user, %{mode: :on_completion, frequency: :days})
      first = occurrence_fixture(user, series, hours_ago(1))

      {:ok, _} = Tasks.update_task(user, first.id, %{title: "Bins"}, command())
      assert later_occurrences(series, first) == []

      {:ok, _} = Tasks.drop_task(user, first.id, command())
      assert [%Task{title: "Bins", state: :to_do}] = later_occurrences(series, first)
    end

    test "reopening keeps the next, and finishing again adds none", %{user: user} do
      series = series_fixture(user, %{mode: :on_completion, frequency: :days})
      first = occurrence_fixture(user, series, hours_ago(1))

      {:ok, _} = Tasks.complete_task(user, first.id, command())
      {:ok, _} = Tasks.reopen_task(user, first.id, command())
      {:ok, _} = Tasks.update_task(user, first.id, %{state: :done}, command(), at: hours_ago(1))
      {:ok, _} = Tasks.drop_task(user, first.id, command())

      assert [%Task{state: :to_do}] = later_occurrences(series, first)
    end

    test "finishing early can give an earlier slot, and that one repeats", %{user: user} do
      series = series_fixture(user, %{mode: :on_completion, frequency: :days})
      first = occurrence_fixture(user, series, DateTime.add(now(), 5, :day))

      {:ok, _} = Tasks.complete_task(user, first.id, command())
      [second] = later_occurrences(series, first)
      assert DateTime.before?(second.occurrence_for, first.occurrence_for)

      age(second)
      {:ok, _} = Tasks.update_task(user, second.id, %{state: :done}, command(), at: hours_ago(1))
      assert [_, _] = later_occurrences(series, first)
    end

    test "a replayed command creates nothing more", %{user: user} do
      series = series_fixture(user, %{mode: :on_completion, frequency: :days})
      first = occurrence_fixture(user, series, hours_ago(1))
      command_id = command()

      {:ok, _} = Tasks.complete_task(user, first.id, command_id)
      changes = Repo.aggregate(Change, :count)
      {:ok, _} = Tasks.complete_task(user, first.id, command_id)

      assert Repo.aggregate(Change, :count) == changes
      assert [_] = later_occurrences(series, first)
    end

    test "a subtask's next stays under its parent", %{user: user} do
      series = series_fixture(user, %{mode: :on_completion, frequency: :days})
      {:ok, parent} = Tasks.create_task(user, %{title: "House"}, command())
      first = occurrence_fixture(user, series, hours_ago(1), %{parent_id: parent.id})

      {:ok, _} = Tasks.complete_task(user, first.id, command())
      assert [%Task{parent_id: parent_id, inbox: true}] = later_occurrences(series, first)
      assert parent_id == parent.id
    end

    test "a client's Done creates it, and the next pull carries it", %{user: user} do
      series = series_fixture(user, %{mode: :on_completion, frequency: :days})
      first = occurrence_fixture(user, series, hours_ago(1))
      cursor = Sync.pull(user, nil).cursor

      assert [%{status: "applied"}] =
               Push.push(user, [
                 %{
                   "id" => command(),
                   "entity" => "task",
                   "entity_id" => first.id,
                   "op" => "patch",
                   "fields" => %{"state" => "done"}
                 }
               ])

      [next] = later_occurrences(series, first)
      ids = Enum.map(Sync.pull(user, cursor).rows["task"], & &1["id"])
      assert next.id in ids
    end

    test "not from a stopped series, past the end, or past the count", %{user: user} do
      stopped = series_fixture(user, %{mode: :on_completion, frequency: :days})
      first = occurrence_fixture(user, stopped, hours_ago(1))
      {:ok, _} = Recurrence.stop_series(user, stopped.id, command())
      {:ok, _} = Tasks.complete_task(user, first.id, command())
      assert later_occurrences(stopped, first) == []

      ended =
        series_fixture(user, %{mode: :on_completion, frequency: :days, ends_at: now()})

      first = occurrence_fixture(user, ended, hours_ago(1))
      {:ok, _} = Tasks.complete_task(user, first.id, command())
      assert later_occurrences(ended, first) == []

      counted = series_fixture(user, %{mode: :on_completion, frequency: :days, end_count: 2})
      first = occurrence_fixture(user, counted, hours_ago(1))
      {:ok, _} = Tasks.complete_task(user, first.id, command())
      [second] = later_occurrences(counted, first)
      age(second)
      {:ok, _} = Tasks.complete_task(user, second.id, command())
      assert [_] = later_occurrences(counted, first)
    end
  end

  describe "regular" do
    test "finishing creates nothing; a passed slot gets the first after now", %{user: user} do
      series = series_fixture(user, %{frequency: :days})
      first = occurrence_fixture(user, series, hours_ago(3 * 24 - 1))

      {:ok, _} = Tasks.complete_task(user, first.id, command())
      assert later_occurrences(series, first) == []

      assert Recurrence.generate(now()) == 1
      [next] = later_occurrences(series, first)
      assert next.occurrence_for == DateTime.add(first.occurrence_for, 3, :day)
      assert next.state == :to_do

      assert Recurrence.generate(now()) == 0
      assert Recurrence.generate(DateTime.add(next.occurrence_for, 1, :second)) == 1
      assert [_, _] = later_occurrences(series, first)
    end

    test "creates the next even while the previous is open", %{user: user} do
      series = series_fixture(user, %{frequency: :hours})
      first = occurrence_fixture(user, series, hours_ago(1))

      assert Recurrence.generate(now()) == 1
      assert [%Task{state: :to_do}] = later_occurrences(series, first)
      assert %Task{state: :to_do} = Tasks.get_task(user, first.id)
    end

    test "stops at the open cap and resumes at the first slot after now", %{user: user} do
      series = series_fixture(user, %{frequency: :hours})
      first = occurrence_fixture(user, series, hours_ago(20))

      for hour <- -18..-10//1, do: Recurrence.generate(hours_ago(-hour))
      assert open_count(series) == Recurrence.open_cap()
      latest = latest_slot(series)

      assert Recurrence.generate(now()) == 0
      {:ok, _} = Tasks.complete_task(user, first.id, command())

      assert Recurrence.generate(now()) == 1
      assert latest_slot(series) == DateTime.add(first.occurrence_for, 21, :hour)
      assert DateTime.diff(latest_slot(series), latest, :hour) == 10
    end

    test "a deleted occurrence does not come back", %{user: user} do
      series = series_fixture(user, %{frequency: :days})
      first = occurrence_fixture(user, series, hours_ago(1))

      assert Recurrence.generate(now()) == 1
      [next] = later_occurrences(series, first)
      {:ok, _} = Tasks.delete_task(user, next.id, command())

      assert Recurrence.generate(DateTime.add(next.occurrence_for, -60, :second)) == 0
      assert Recurrence.generate(DateTime.add(next.occurrence_for, 60, :second)) == 1
      assert [%Task{occurrence_for: slot}] = later_occurrences(series, first)
      assert slot == DateTime.add(next.occurrence_for, 1, :day)
    end

    test "end count includes the first, and the end date its own slot", %{user: user} do
      counted = series_fixture(user, %{frequency: :days, end_count: 2})
      occurrence_fixture(user, counted, hours_ago(1))
      ends = DateTime.add(hours_ago(1), 1, :day)
      ended = series_fixture(user, %{frequency: :days, ends_at: ends})
      occurrence_fixture(user, ended, hours_ago(1))

      assert Recurrence.generate(now()) == 2
      assert Recurrence.generate(DateTime.add(now(), 2, :day)) == 0
    end

    test "not from a stopped series or one with no live occurrence", %{user: user} do
      stopped = series_fixture(user, %{frequency: :days})
      occurrence_fixture(user, stopped, hours_ago(1))
      {:ok, _} = Recurrence.stop_series(user, stopped.id, command())

      emptied = series_fixture(user, %{frequency: :days})
      gone = occurrence_fixture(user, emptied, hours_ago(1))
      {:ok, _} = Tasks.delete_task(user, gone.id, command())

      assert Recurrence.generate(now()) == 0
    end

    test "the job runs the generator", %{user: user} do
      series = series_fixture(user, %{frequency: :days})
      first = occurrence_fixture(user, series, hours_ago(1))

      assert :ok = perform_job(Recurrence.GenerateJob, %{})
      assert [_] = later_occurrences(series, first)
    end
  end

  defp series_fixture(user, attrs) do
    {:ok, series} =
      Recurrence.create_series(
        user,
        Map.merge(%{kind: :task, mode: :regular, anchor: :due, interval: 1}, attrs),
        command()
      )

    series
  end

  defp occurrence_fixture(user, series, due, attrs \\ %{}) do
    {:ok, task} =
      Tasks.create_task(
        user,
        Map.merge(
          %{title: "Trash", due_at: due, series_id: series.id, occurrence_for: due},
          attrs
        ),
        command()
      )

    age(task, 3600)
  end

  # Timestamps are whole seconds, and the latest occurrence is the one
  # created last.
  defp age(task, seconds \\ 60) do
    inserted_at = DateTime.add(task.inserted_at, -seconds, :second)
    Repo.update_all(from(t in Task, where: t.id == ^task.id), set: [inserted_at: inserted_at])
    %{task | inserted_at: inserted_at}
  end

  defp later_occurrences(series, first) do
    Repo.all(
      from t in Task,
        where: t.series_id == ^series.id and t.id != ^first.id and is_nil(t.discarded_at),
        order_by: t.inserted_at
    )
  end

  defp open_count(series) do
    Repo.aggregate(
      from(t in Task, where: t.series_id == ^series.id and t.state == :to_do),
      :count
    )
  end

  defp latest_slot(series) do
    Repo.one(from t in Task, where: t.series_id == ^series.id, select: max(t.occurrence_for))
  end

  defp now, do: DateTime.utc_now(:second)
  defp hours_ago(hours), do: DateTime.add(now(), -hours, :hour)
  defp command, do: Ecto.UUID.generate()
end
