defmodule Marskal.Recurrence.NextOccurrenceTest do
  use Marskal.DataCase, async: true

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
          flagged: true,
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
               flagged: true,
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

    test "subtasks are copied under the next, To-Do, dates shifted", %{user: user} do
      series = series_fixture(user, %{mode: :on_completion, frequency: :days, interval: 7})
      {:ok, tag} = Tags.create_tag(user, %{name: "shop"}, command())
      due = hours_ago(1)
      first = occurrence_fixture(user, series, due)

      {:ok, gift} =
        Tasks.create_task(
          user,
          %{
            title: "Gift",
            parent_id: first.id,
            notes: "Ask first",
            flagged: true,
            due_at: DateTime.add(due, -2, :day)
          },
          command()
        )

      {:ok, wrap} = Tasks.create_task(user, %{title: "Wrap", parent_id: gift.id}, command())
      {:ok, card} = Tasks.create_task(user, %{title: "Card", parent_id: first.id}, command())
      {:ok, gone} = Tasks.create_task(user, %{title: "Gone", parent_id: first.id}, command())
      {:ok, _} = Tags.tag_task(user, gift.id, tag.id, command())
      {:ok, _} = Tasks.complete_task(user, wrap.id, command())
      {:ok, _} = Tasks.drop_task(user, card.id, command())
      {:ok, _} = Tasks.delete_task(user, gone.id, command())
      {:ok, _} = Tasks.complete_task(user, first.id, command())

      [next] = later_occurrences(series, first)
      gift_id = Marskal.Uuid.v5(next.id, gift.id)

      assert [
               %Task{id: ^gift_id, title: "Gift", notes: "Ask first", flagged: true} = gift_copy,
               %Task{title: "Card", state: :to_do, series_id: nil}
             ] = Tasks.Outline.children(next)

      assert [%Task{title: "Wrap", state: :to_do}] = Tasks.Outline.children(gift_copy)
      assert gift_copy.inbox == next.inbox

      zone = "Europe/Copenhagen"
      {next_day, _} = Dates.to_local(next.due_at, zone)
      {gift_day, gift_time} = Dates.to_local(gift_copy.due_at, zone)
      {_, source_time} = Dates.to_local(gift.due_at, zone)
      assert Date.diff(next_day, gift_day) == 2
      assert gift_time == source_time

      assert [tag.id] ==
               Repo.all(
                 from l in TaskTag,
                   where: l.task_id == ^gift_copy.id and is_nil(l.discarded_at),
                   select: l.tag_id
               )

      # The old tree stays as it was.
      assert [%Task{id: wrap_id, state: :done}] = Tasks.Outline.children(gift)
      assert wrap_id == wrap.id
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
    test "Done creates the slot after the one resolved, and To-Do does not", %{user: user} do
      series = series_fixture(user, %{frequency: :days})
      first = occurrence_fixture(user, series, hours_ago(1))

      {:ok, _} = Tasks.update_task(user, first.id, %{title: "Bins"}, command())
      assert later_occurrences(series, first) == []

      {:ok, _} = Tasks.complete_task(user, first.id, command())
      [next] = later_occurrences(series, first)
      slot = DateTime.add(first.occurrence_for, 1, :day)
      assert next.id == Recurrence.occurrence_id(series.id, slot)
      assert %Task{title: "Bins", state: :to_do, due_at: ^slot, occurrence_for: ^slot} = next
    end

    test "finishing early still takes the slot after this one", %{user: user} do
      series = series_fixture(user, %{frequency: :weeks})
      first = occurrence_fixture(user, series, DateTime.add(now(), 2, :day))

      {:ok, _} = Tasks.drop_task(user, first.id, command())
      assert [%Task{occurrence_for: slot}] = later_occurrences(series, first)
      assert slot == DateTime.add(first.occurrence_for, 7, :day)
    end

    test "finishing late skips the slots that passed", %{user: user} do
      series = series_fixture(user, %{frequency: :days})
      first = occurrence_fixture(user, series, hours_ago(3 * 24 - 1))

      {:ok, _} = Tasks.complete_task(user, first.id, command())
      assert [%Task{occurrence_for: slot}] = later_occurrences(series, first)
      assert slot == DateTime.add(first.occurrence_for, 3, :day)
    end

    test "done by mistake, undone, and done again creates one", %{user: user} do
      for due <- [hours_ago(1), DateTime.add(now(), 2, :day)] do
        series = series_fixture(user, %{frequency: :days})
        first = occurrence_fixture(user, series, due)

        {:ok, _} = Tasks.complete_task(user, first.id, command())
        [second] = later_occurrences(series, first)
        {:ok, _} = Tasks.reopen_task(user, first.id, command())
        assert later_occurrences(series, first) == [second]

        # The second is the latest now, so finishing the first again, or
        # dropping it, adds nothing.
        {:ok, _} = Tasks.complete_task(user, first.id, command())
        {:ok, _} = Tasks.reopen_task(user, first.id, command())
        {:ok, _} = Tasks.drop_task(user, first.id, command())

        assert [%Task{id: id, state: :to_do}] = later_occurrences(series, first)
        assert id == second.id
      end
    end

    test "not past the end count or the end date", %{user: user} do
      counted = series_fixture(user, %{frequency: :days, end_count: 1})
      first = occurrence_fixture(user, counted, hours_ago(1))
      {:ok, _} = Tasks.complete_task(user, first.id, command())
      assert later_occurrences(counted, first) == []

      ended = series_fixture(user, %{frequency: :days, ends_at: now()})
      first = occurrence_fixture(user, ended, hours_ago(1))
      {:ok, _} = Tasks.complete_task(user, first.id, command())
      assert later_occurrences(ended, first) == []
    end
  end

  describe "pause and resume" do
    test "resuming after the latest was resolved creates the next from now", %{user: user} do
      series = series_fixture(user, %{frequency: :hours})
      first = occurrence_fixture(user, series, hours_ago(5))
      {:ok, _} = Recurrence.stop_series(user, series.id, command())
      {:ok, _} = Tasks.complete_task(user, first.id, command())
      assert later_occurrences(series, first) == []

      {:ok, _} = Recurrence.update_series(user, series.id, %{stopped_at: nil}, command())
      assert [%Task{occurrence_for: slot}] = later_occurrences(series, first)
      assert slot == DateTime.add(first.occurrence_for, 6, :hour)
    end

    test "resuming with the latest open creates none", %{user: user} do
      series = series_fixture(user, %{mode: :on_completion, frequency: :days})
      first = occurrence_fixture(user, series, hours_ago(1))
      {:ok, _} = Recurrence.stop_series(user, series.id, command())
      {:ok, _} = Recurrence.update_series(user, series.id, %{stopped_at: nil}, command())

      assert later_occurrences(series, first) == []
    end
  end

  describe "deleting" do
    test "the latest occurrence ends the series, and its history stays", %{user: user} do
      series = series_fixture(user, %{frequency: :days})
      first = occurrence_fixture(user, series, hours_ago(1))
      {:ok, _} = Tasks.complete_task(user, first.id, command())
      [next] = later_occurrences(series, first)

      {:ok, _} = Tasks.delete_task(user, next.id, command())

      assert Recurrence.get_series(user, series.id) == nil
      assert %Task{state: :done, series_id: series_id} = Tasks.get_task(user, first.id)
      assert series_id == series.id
    end

    test "an earlier occurrence leaves the series as it is", %{user: user} do
      series = series_fixture(user, %{frequency: :days})
      first = occurrence_fixture(user, series, hours_ago(1))
      {:ok, _} = Tasks.complete_task(user, first.id, command())

      {:ok, _} = Tasks.delete_task(user, first.id, command())
      assert Recurrence.get_series(user, series.id)
    end

    test "a paused series ends too, as does one under a deleted parent", %{user: user} do
      paused = series_fixture(user, %{frequency: :days})
      occurrence = occurrence_fixture(user, paused, hours_ago(1))
      {:ok, _} = Recurrence.stop_series(user, paused.id, command())
      {:ok, _} = Tasks.delete_task(user, occurrence.id, command())
      assert Recurrence.get_series(user, paused.id) == nil

      nested = series_fixture(user, %{frequency: :days})
      {:ok, parent} = Tasks.create_task(user, %{title: "House"}, command())
      occurrence_fixture(user, nested, hours_ago(1), %{parent_id: parent.id})
      {:ok, _} = Tasks.delete_task(user, parent.id, command())
      assert Recurrence.get_series(user, nested.id) == nil
    end

    test "a client's delete ends it, and the next pull carries the series", %{user: user} do
      series = series_fixture(user, %{frequency: :days})
      first = occurrence_fixture(user, series, hours_ago(1))
      cursor = Sync.pull(user, nil).cursor

      assert [%{status: "applied"}] =
               Push.push(user, [
                 %{
                   "id" => command(),
                   "entity" => "task",
                   "entity_id" => first.id,
                   "op" => "patch",
                   "fields" => %{"discarded_at" => DateTime.to_iso8601(now())}
                 }
               ])

      assert Recurrence.get_series(user, series.id) == nil
      ids = Enum.map(Sync.pull(user, cursor).rows["recurrence_series"], & &1["id"])
      assert series.id in ids
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

  defp now, do: DateTime.utc_now(:second)
  defp hours_ago(hours), do: DateTime.add(now(), -hours, :hour)
  defp command, do: Ecto.UUID.generate()
end
