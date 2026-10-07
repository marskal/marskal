defmodule Marskal.Recurrence.ScheduleTest do
  use ExUnit.Case, async: true

  alias Marskal.Dates
  alias Marskal.Recurrence.Schedule
  alias Marskal.Recurrence.Series

  @zone "Europe/Copenhagen"

  @rule %{
    mode: :regular,
    anchor: :due,
    interval: 1,
    frequency: :days,
    weekdays: [],
    month_days: []
  }

  describe "minutes and hours" do
    test "add elapsed time" do
      from = ~U[2026-05-01 10:00:00Z]

      assert slot(%{frequency: :minutes, interval: 36}, from) == ~U[2026-05-01 10:36:00Z]
      assert slot(%{frequency: :hours, interval: 36}, from) == ~U[2026-05-02 22:00:00Z]
    end

    test "keep elapsed time across a DST change, where a calendar day does not" do
      from = at(~D[2026-03-28], ~T[17:00:00])

      assert slot(%{frequency: :hours, interval: 24}, from) ==
               DateTime.add(from, 24 * 3600, :second)

      refute slot(%{frequency: :days, interval: 1}, from) ==
               slot(%{frequency: :hours, interval: 24}, from)
    end
  end

  describe "days" do
    test "steps on the calendar and keeps the local time" do
      assert slot(%{interval: 3}, ~D[2026-10-09]) == at(~D[2026-10-12])
    end

    test "a skipped local time moves forward, and a repeated one takes the first" do
      assert slot(%{}, at(~D[2026-03-28], ~T[02:30:00])) ==
               at(~D[2026-03-29], ~T[02:30:00])

      assert slot(%{}, at(~D[2026-10-24], ~T[02:30:00])) ==
               at(~D[2026-10-25], ~T[02:30:00])
    end

    test "uses the zone's calendar, including across another zone's DST change" do
      zone = "America/New_York"
      from = Dates.from_local(~D[2026-03-07], ~T[17:00:00], :due_at, zone)

      assert Schedule.next_slot(rule(%{frequency: :weeks}), from, zone) ==
               Dates.from_local(~D[2026-03-14], ~T[17:00:00], :due_at, zone)
    end
  end

  describe "weeks" do
    test "without listed days, adds that many weeks" do
      for mode <- [:regular, :on_completion] do
        assert slot(%{mode: mode, frequency: :weeks, interval: 2}, ~D[2026-03-27]) ==
                 at(~D[2026-04-10])
      end
    end

    test "every week on Mon, Wed, and Fri takes the next of those days" do
      rule = %{frequency: :weeks, weekdays: [1, 3, 5]}

      assert slot(rule, ~D[2026-10-05]) == at(~D[2026-10-07])
      assert slot(rule, ~D[2026-10-07]) == at(~D[2026-10-09])
      assert slot(rule, ~D[2026-10-09]) == at(~D[2026-10-12])
    end

    test "every 2 weeks on Tue and Thu stays on that week's grid" do
      rule = %{frequency: :weeks, interval: 2, weekdays: [2, 4]}

      assert slot(rule, ~D[2026-10-06]) == at(~D[2026-10-08])
      assert slot(rule, ~D[2026-10-07]) == at(~D[2026-10-08])
      assert slot(rule, ~D[2026-10-08]) == at(~D[2026-10-20])
    end

    test "a first slot that is not a listed day waits for the next grid week" do
      rule = %{frequency: :weeks, interval: 2, weekdays: [2, 4]}

      assert slot(rule, ~D[2026-10-09]) == at(~D[2026-10-20])

      mondays = %{frequency: :weeks, interval: 2, weekdays: [1]}
      assert slot(mondays, ~D[2026-10-11]) == at(~D[2026-10-19])
    end
  end

  describe "months" do
    test "keeps the day of the month, and skips a month that lacks it" do
      assert slot(%{frequency: :months}, ~D[2026-01-15]) == at(~D[2026-02-15])
      assert slot(%{frequency: :months}, ~D[2026-01-31]) == at(~D[2026-03-31])
      assert slot(%{frequency: :months, interval: 2}, ~D[2026-01-31]) == at(~D[2026-03-31])
    end

    test "listed days, including the last day, are the set the slot lands on" do
      days = %{frequency: :months, month_days: [1, 15]}

      assert slot(days, ~D[2026-01-10]) == at(~D[2026-01-15])
      assert slot(days, ~D[2026-01-15]) == at(~D[2026-02-01])

      last = %{frequency: :months, month_days: [-1]}
      assert slot(last, ~D[2026-01-31]) == at(~D[2026-02-28])
      assert slot(last, ~D[2026-02-28]) == at(~D[2026-03-31])

      both = %{frequency: :months, month_days: [-1, 31]}
      assert slot(both, ~D[2026-01-31]) == at(~D[2026-02-28])
      assert slot(both, ~D[2026-02-28]) == at(~D[2026-03-31])
    end

    test "steps listed days by the interval, from the month it started in" do
      rule = %{frequency: :months, interval: 2, month_days: [1, 15]}

      assert slot(rule, ~D[2026-01-10]) == at(~D[2026-01-15])
      assert slot(rule, ~D[2026-01-15]) == at(~D[2026-03-01])
    end

    test "an nth weekday, work day, or weekend day" do
      third_friday = %{frequency: :months, month_ordinal: 3, month_day_kind: :friday}
      assert slot(third_friday, ~D[2026-10-01]) == at(~D[2026-10-16])
      assert slot(third_friday, ~D[2026-10-16]) == at(~D[2026-11-20])

      fifth_monday = %{frequency: :months, month_ordinal: 5, month_day_kind: :monday}
      assert slot(fifth_monday, ~D[2026-01-15]) == at(~D[2026-03-30])

      assert slot(
               %{frequency: :months, month_ordinal: 1, month_day_kind: :work_day},
               ~D[2026-08-20]
             ) ==
               at(~D[2026-09-01])

      assert slot(
               %{frequency: :months, month_ordinal: -1, month_day_kind: :work_day},
               ~D[2026-05-01]
             ) ==
               at(~D[2026-05-29])

      assert slot(
               %{frequency: :months, month_ordinal: 1, month_day_kind: :weekend_day},
               ~D[2026-05-01]
             ) == at(~D[2026-05-02])

      assert slot(
               %{frequency: :months, month_ordinal: -1, month_day_kind: :weekend_day},
               ~D[2026-05-02]
             ) == at(~D[2026-05-31])
    end

    test "a calendar day and an nth day together are one set" do
      first_monday = %{
        frequency: :months,
        month_days: [20],
        month_ordinal: 1,
        month_day_kind: :monday
      }

      assert slot(first_monday, ~D[2026-01-01]) == at(~D[2026-01-05])
      assert slot(first_monday, ~D[2026-01-05]) == at(~D[2026-01-20])
      assert slot(first_monday, ~D[2026-01-20]) == at(~D[2026-02-02])

      payday = %{
        frequency: :months,
        month_days: [15],
        month_ordinal: -1,
        month_day_kind: :work_day
      }

      assert slot(payday, ~D[2026-05-01]) == at(~D[2026-05-15])
      assert slot(payday, ~D[2026-05-15]) == at(~D[2026-05-29])
      assert slot(payday, ~D[2026-05-29]) == at(~D[2026-06-15])
    end

    test "the 15th after a 31st is the 15th of the next month" do
      rule = %{frequency: :months, month_days: [15]}

      assert slot(rule, ~D[2026-01-10]) == at(~D[2026-01-15])
      assert slot(rule, ~D[2026-01-20]) == at(~D[2026-02-15])
      assert slot(rule, ~D[2026-01-31]) == at(~D[2026-02-15])

      every_two = %{frequency: :months, interval: 2, month_days: [15]}
      assert slot(every_two, ~D[2026-01-10]) == at(~D[2026-01-15])
      assert slot(every_two, ~D[2026-01-20]) == at(~D[2026-03-15])
    end
  end

  describe "years" do
    test "keeps the month and day, and a regular rule skips a year that lacks it" do
      for mode <- [:regular, :on_completion] do
        assert slot(%{mode: mode, frequency: :years}, ~D[2026-03-01]) == at(~D[2027-03-01])

        assert slot(%{mode: mode, frequency: :years, interval: 4}, ~D[2024-02-29]) ==
                 at(~D[2028-02-29])
      end

      assert slot(%{frequency: :years}, ~D[2024-02-29]) == at(~D[2028-02-29])
    end
  end

  describe "on completion" do
    test "a short month or year clamps to its last day" do
      rule = %{mode: :on_completion, frequency: :months}

      assert slot(rule, ~D[2026-01-15]) == at(~D[2026-02-15])
      assert slot(rule, ~D[2026-01-31]) == at(~D[2026-02-28])
      assert slot(Map.put(rule, :interval, 2), ~D[2026-01-31]) == at(~D[2026-03-31])

      assert slot(%{mode: :on_completion, frequency: :years}, ~D[2024-02-29]) ==
               at(~D[2025-02-28])
    end
  end

  describe "an end date" do
    test "a slot on the end instant is kept, and one after it is not" do
      ends = at(~D[2026-10-12])

      assert slot(%{frequency: :weeks, ends_at: ends}, ~D[2026-10-05]) == ends

      assert slot(%{frequency: :weeks, ends_at: DateTime.add(ends, -1, :second)}, ~D[2026-10-05]) ==
               nil
    end

    test "a month the rule skipped is not a slot that sneaks in before the end" do
      assert slot(
               %{frequency: :months, month_days: [31], ends_at: at(~D[2026-02-28])},
               ~D[2026-01-31]
             ) == nil

      assert slot(
               %{frequency: :months, month_days: [31], ends_at: at(~D[2026-03-31])},
               ~D[2026-01-31]
             ) == at(~D[2026-03-31])
    end
  end

  describe "other dates" do
    test "keep their distance from the anchor on the zone clock" do
      latest = %{
        defer_until: at(~D[2026-03-25], ~T[09:00:00]),
        planned_at: at(~D[2026-03-28], ~T[09:00:00]),
        due_at: at(~D[2026-03-27], ~T[17:00:00])
      }

      slot = at(~D[2026-04-03], ~T[17:00:00])

      assert Schedule.shift_dates(latest, :due, slot, @zone) == %{
               defer_until: at(~D[2026-04-01], ~T[09:00:00]),
               planned_at: at(~D[2026-04-04], ~T[09:00:00]),
               due_at: slot
             }
    end

    test "a same-day offset keeps its local time across the spring change" do
      latest = %{
        defer_until: at(~D[2026-03-29], ~T[01:30:00]),
        planned_at: nil,
        due_at: at(~D[2026-03-29], ~T[17:00:00])
      }

      slot = at(~D[2026-04-05], ~T[17:00:00])
      shifted = Schedule.shift_dates(latest, :due, slot, @zone)

      assert shifted.defer_until == at(~D[2026-04-05], ~T[01:30:00])
      assert shifted.planned_at == nil
      assert shifted.due_at == slot

      elapsed = DateTime.add(slot, DateTime.diff(latest.defer_until, latest.due_at), :second)
      refute shifted.defer_until == elapsed
    end

    test "an unset date stays unset, and a missing anchor leaves the others" do
      planned = at(~D[2026-10-10])
      slot = at(~D[2026-10-16])

      assert Schedule.shift_dates(
               %{defer_until: nil, planned_at: nil, due_at: at(~D[2026-10-09])},
               :due,
               slot,
               @zone
             ) == %{defer_until: nil, planned_at: nil, due_at: slot}

      assert Schedule.shift_dates(
               %{defer_until: nil, planned_at: planned, due_at: nil},
               :due,
               slot,
               @zone
             ).planned_at == planned
    end

    test "the anchor can be defer or planned" do
      latest = %{
        defer_until: at(~D[2026-10-07], ~T[09:00:00]),
        planned_at: at(~D[2026-10-09], ~T[09:00:00]),
        due_at: at(~D[2026-10-10], ~T[17:00:00])
      }

      slot = at(~D[2026-10-16], ~T[09:00:00])

      assert Schedule.shift_dates(latest, :planned, slot, @zone) == %{
               defer_until: at(~D[2026-10-14], ~T[09:00:00]),
               planned_at: slot,
               due_at: at(~D[2026-10-17], ~T[17:00:00])
             }
    end
  end

  test "every rule lands strictly after the instant it steps from" do
    from = at(~D[2026-01-31])

    rules = [
      %{frequency: :minutes, interval: 1},
      %{frequency: :hours, interval: 36},
      %{frequency: :days, interval: 1},
      %{frequency: :weeks, interval: 2, weekdays: [2, 4]},
      %{frequency: :months, interval: 1, month_days: [31]},
      %{frequency: :months, interval: 1, month_ordinal: 5, month_day_kind: :monday},
      %{frequency: :years, interval: 1},
      %{mode: :on_completion, frequency: :weeks, interval: 2},
      %{mode: :on_completion, frequency: :months, interval: 1}
    ]

    for attrs <- rules do
      assert DateTime.after?(slot(attrs, from), from), inspect(attrs)
    end
  end

  defp slot(attrs, %Date{} = from), do: slot(attrs, at(from))

  defp slot(attrs, %DateTime{} = from) do
    Schedule.next_slot(rule(attrs), from, @zone)
  end

  defp rule(attrs), do: struct!(Series, Map.merge(@rule, attrs))

  defp at(date, time \\ ~T[17:00:00]), do: Dates.from_local(date, time, :due_at, @zone)
end
