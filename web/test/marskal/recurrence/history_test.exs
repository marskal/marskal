defmodule Marskal.Recurrence.HistoryTest do
  use ExUnit.Case, async: true

  alias Marskal.Recurrence.History
  alias Marskal.Recurrence.Series

  @zone "Europe/Copenhagen"
  # 17:00 in Copenhagen, summer time.
  @time ~T[15:00:00]

  @daily %Series{
    mode: :regular,
    anchor: :due,
    interval: 1,
    frequency: :days,
    weekdays: [],
    on_days: [],
    week_start: 1
  }

  @keep :math.pow(0.5, 1 / 7)

  test "nothing yet" do
    history = History.build(@daily, [], day(1), @zone)

    assert %History{
             entries: [],
             strength: +0.0,
             streak: 0,
             best_streak: 0,
             rate: nil,
             lateness: nil
           } =
             history
  end

  test "done on time, every slot" do
    occurrences = [done(1, hours: 1), done(2, hours: 2), done(3, hours: 3)]
    history = History.build(@daily, occurrences, day(3, hours: 4), @zone)

    assert %History{streak: 3, best_streak: 3, done: 3, dropped: 0, missed: 0, rate: 1.0} =
             history

    assert_in_delta history.strength, 1 - @keep ** 3, 1.0e-9
    assert [_, _, _] = history.trend
    assert history.lateness == 2 * 3600
    assert Enum.map(history.entries, &slot_of/1) == [day(3), day(2), day(1)]
  end

  test "slots that pass while an occurrence is open are missed, and end the streak" do
    occurrences = [done(1, hours: 1), done(2, days: 1, hours: 1), done(4, hours: 1)]
    history = History.build(@daily, occurrences, day(4, hours: 2), @zone)

    assert %History{done: 3, missed: 1, streak: 2, best_streak: 2} = history
    assert_in_delta history.rate, 3 / 4, 1.0e-9

    assert [{:occurrence, _}, {:missed, [missed]}, {:occurrence, _}, {:occurrence, _}] =
             history.entries

    assert missed == day(3)
  end

  test "dropped neither extends nor breaks a streak, nor moves strength" do
    occurrences = [done(1), dropped(2), done(3)]
    history = History.build(@daily, occurrences, day(3, hours: 1), @zone)

    assert %History{streak: 2, best_streak: 2, done: 2, dropped: 1, missed: 0} = history
    assert_in_delta history.strength, 1 - @keep ** 2, 1.0e-9
    assert_in_delta history.rate, 2 / 3, 1.0e-9
  end

  test "slots a pause skipped count for nothing" do
    # Resolved on time on the 1st, paused, resumed on the 5th at noon.
    occurrences = [done(1, hours: 3), done(5, hours: 1)]
    history = History.build(@daily, occurrences, day(5, hours: 2), @zone)

    assert %History{missed: 0, streak: 2, done: 2} = history
    assert [{:occurrence, _}, {:paused, 3}, {:occurrence, _}] = history.entries
  end

  test "the open latest misses slots up to now" do
    occurrences = [done(1), open(2)]
    history = History.build(@daily, occurrences, day(4, hours: 1), @zone)

    assert %History{missed: 2, streak: 0, best_streak: 1} = history

    assert [{:missed, [_, _]}, {:occurrence, %{state: :to_do}}, {:occurrence, _}] =
             history.entries
  end

  test "on completion, each whole interval left open is missed, and a longer wait was a pause" do
    every_3_days = %{@daily | mode: :on_completion, interval: 3}

    # Due on the 1st, done on the 8th: the 4th and the 7th passed. Then a
    # pause: the next came on the 20th, not the 11th.
    occurrences = [done(1, days: 7), open(20)]
    history = History.build(every_3_days, occurrences, day(20), @zone)

    assert %History{missed: 2, done: 1, streak: 1} = history

    assert [{:occurrence, _}, {:paused, 3}, {:missed, [fourth, seventh]}, {:occurrence, _}] =
             history.entries

    assert {fourth, seventh} == {day(4), day(7)}
  end

  test "strength dips at a miss and recovers with Done" do
    # The 4th is done a day late, so the 5th is missed.
    occurrences =
      [done(1), done(2), done(3), done(4, days: 1, hours: 1)] ++ for(n <- 6..12, do: done(n))

    history = History.build(@daily, occurrences, day(12, hours: 1), @zone)

    assert history.missed == 1
    {before, [dip | after_dip]} = Enum.split(history.trend, 3)
    assert dip < List.last(before)
    assert List.last(after_dip) > List.last(before)
  end

  test "lateness is the median over Done, and negative when early" do
    occurrences = [done(1, hours: -2), done(2, hours: 1), dropped(3, hours: 9), done(4, hours: 5)]
    assert History.build(@daily, occurrences, day(5), @zone).lateness == 3600

    assert History.build(@daily, [done(1, hours: -2), done(2, hours: -4)], day(3), @zone).lateness ==
             -3 * 3600
  end

  defp slot_of({:occurrence, occurrence}), do: occurrence.occurrence_for

  defp done(n, after_slot \\ []), do: occurrence(n, :done, after_slot)
  defp dropped(n, after_slot \\ []), do: occurrence(n, :dropped, after_slot)
  defp open(n), do: %{state: :to_do, occurrence_for: day(n), resolved_at: nil}

  defp occurrence(n, state, after_slot) do
    %{state: state, occurrence_for: day(n), resolved_at: day(n, after_slot)}
  end

  defp day(n, offset \\ []) do
    DateTime.new!(Date.new!(2026, 9, n), @time)
    |> DateTime.add(
      Keyword.get(offset, :days, 0) * 86_400 + Keyword.get(offset, :hours, 0) * 3600
    )
  end
end
