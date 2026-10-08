defmodule Marskal.Recurrence.Schedule do
  @moduledoc """
  The next slot a rule produces, and the dates that move with it
  (ADR 0007, ADR 0014).

  A pure function of the rule, the instant it steps from, and the user's
  timezone. It does not read or write the database. Creating the task for
  a slot is a later step.

  `from` is the previous occurrence's slot in regular mode, and the
  resolution time in on-completion mode. Regular mode expands the rule as
  RFC 5545 does: `from` starts the rule, and the result is the next instance strictly after it. On
  completion adds the interval to `from`, and a short month or year
  clamps to its last day, since that day came from the resolution time.
  On completion has no day limits.

  Minutes and hours are elapsed time. Days, weeks, months, and years step
  on the zone's calendar and keep the local time, so a weekly 17:00 stays
  17:00 across a DST change. A time the change skips moves forward, and a
  repeated one takes the first, as `Marskal.Dates.from_local/4` does.

  Weekly limits are ISO weekdays (Monday is 1). Every 2 weeks on Tue and
  Thu lands on both days of the start's week, then those days again two
  weeks later. The week starts on the series' `week_start` (RFC 5545's
  WKST), so every 2 weeks on Sun and Mon is two days in a row when weeks
  start on Sunday, and six days apart when they start on Monday.

  Monthly limits are calendar days (1–31, and −1 for the last) and one
  nth weekday, work day, or weekend day. A work day is Monday to Friday.
  Together they are the set of days the slot may land on. With neither,
  the slot keeps the day of the month. A day the month does not have is
  skipped, so the month after a 31st is March. Months step by `interval`
  from `from`'s month.

  The result is nil when the slot would fall after `ends_at`. A slot on
  `ends_at` is kept. The count of occurrences already generated, and the
  cap on open ones, belong to the step that creates the task
  (`Marskal.Recurrence`).
  """

  alias Marskal.Dates
  alias Marskal.Recurrence.Series

  @date_fields [:defer_until, :planned_at, :due_at]
  @weekday %{
    monday: 1,
    tuesday: 2,
    wednesday: 3,
    thursday: 4,
    friday: 5,
    saturday: 6,
    sunday: 7
  }

  @doc """
  The next `occurrence_for` after `from`, in UTC, or nil when that slot
  would be after the series' `ends_at`.

  See the module docs for which instant `from` is, and for how limits and
  a missing day of the month behave.
  """
  def next_slot(%Series{} = series, %DateTime{} = from, zone) when is_binary(zone) do
    from = from |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second)

    case series.frequency do
      :minutes -> elapsed(from, series.interval * 60, series.ends_at)
      :hours -> elapsed(from, series.interval * 3600, series.ends_at)
      _frequency -> calendar(series, from, zone)
    end
  end

  @doc """
  The first slot strictly after `now`, stepping from `from` as
  `next_slot/3` does, or nil when the rule ends first. The slots in
  between are skipped.
  """
  def first_slot_after(%Series{} = series, %DateTime{} = from, %DateTime{} = now, zone) do
    from = from |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second)
    now = now |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second)

    case series.frequency do
      :minutes -> elapsed_after(from, now, series.interval * 60, series.ends_at)
      :hours -> elapsed_after(from, now, series.interval * 3600, series.ends_at)
      _frequency -> step_after(series, from, now, zone)
    end
  end

  @doc """
  The dates of the occurrence at `slot`.

  `anchor` is `:defer`, `:planned`, or `:due`, and that field becomes
  `slot`. Each other date set on `latest` keeps its distance from the
  anchor field on the zone clock: the same number of calendar days, and
  its own local time. A date `latest` does not have stays unset. With no
  anchor instant to measure from, the other dates are copied unchanged.
  """
  def shift_dates(latest, anchor, %DateTime{} = slot, zone)
      when anchor in [:defer, :planned, :due] and is_binary(zone) do
    field = Series.anchor_field(%Series{anchor: anchor})
    anchor_at = Map.get(latest, field)
    slot = slot |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second)

    Map.new(@date_fields, fn
      ^field -> {field, slot}
      other -> {other, shift_field(Map.get(latest, other), anchor_at, slot, zone)}
    end)
  end

  defp calendar(series, from, zone) do
    {date, time} = Dates.to_local(from, zone)
    finish(next_date(date, series), time, zone, series.ends_at)
  end

  # The resolution day is not one the user chose, so a short month or year
  # clamps to its last day instead of being skipped.
  defp next_date(date, %Series{mode: :on_completion, frequency: frequency, interval: interval}) do
    case frequency do
      :days -> Date.add(date, interval)
      :weeks -> Date.add(date, interval * 7)
      :months -> add_months(date, interval)
      :years -> add_months(date, interval * 12)
    end
  end

  defp next_date(date, %Series{mode: :regular} = series) do
    case series.frequency do
      :days -> Date.add(date, series.interval)
      :weeks -> next_week(date, series)
      :months -> next_month(date, series)
      :years -> next_year(date, series.interval)
    end
  end

  defp next_week(date, %Series{weekdays: []} = series) do
    Date.add(date, series.interval * 7)
  end

  # The week grid starts at `date`'s week, and the search the day after it.
  defp next_week(date, %Series{interval: interval, weekdays: weekdays} = series) do
    week_start = week_start(series)
    origin_week = Date.beginning_of_week(date, week_start)

    Enum.find_value(1..(interval * 7 + 6), fn offset ->
      candidate = Date.add(date, offset)
      week = Date.beginning_of_week(candidate, week_start)
      weeks = div(Date.diff(week, origin_week), 7)

      if rem(weeks, interval) == 0 and Date.day_of_week(candidate, :monday) in weekdays do
        candidate
      end
    end)
  end

  defp week_start(%Series{week_start: day}) do
    Enum.find_value(@weekday, fn {name, number} -> if number == day, do: name end)
  end

  defp next_month(date, %Series{month_days: [], month_ordinal: nil} = series) do
    next_month_day(date, series.interval, date.day)
  end

  defp next_month(date, series) do
    Enum.find_value(0..480, fn step ->
      {year, month} = shift_months(date, step * series.interval)

      series
      |> matching_days(year, month)
      |> Enum.find(&Date.after?(&1, date))
    end)
  end

  # The calendar days and the nth day together are the days the slot may
  # land on.
  defp matching_days(series, year, month) do
    start = Date.new!(year, month, 1)
    last = Date.days_in_month(start)

    numbered =
      for day <- series.month_days,
          date = calendar_day(year, month, day, last),
          not is_nil(date),
          do: date

    nth =
      case series.month_ordinal do
        nil -> []
        ordinal -> List.wrap(nth_day(start, ordinal, series.month_day_kind))
      end

    numbered
    |> Enum.concat(nth)
    |> Enum.uniq()
    |> Enum.sort(Date)
  end

  defp calendar_day(year, month, -1, last), do: Date.new!(year, month, last)

  defp calendar_day(year, month, day, _last) do
    case Date.new(year, month, day) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp nth_day(start, ordinal, kind) do
    matches = Enum.filter(Date.range(start, Date.end_of_month(start)), &day_kind?(&1, kind))

    case ordinal do
      -1 -> List.last(matches)
      n -> Enum.at(matches, n - 1)
    end
  end

  defp day_kind?(date, :work_day), do: Date.day_of_week(date, :monday) in 1..5
  defp day_kind?(date, :weekend_day), do: Date.day_of_week(date, :monday) in 6..7
  defp day_kind?(date, kind), do: Date.day_of_week(date, :monday) == Map.fetch!(@weekday, kind)

  # The same day of a later month. A month without that day is skipped,
  # and the interval is kept, so the 31st does not become the 28th.
  defp next_month_day(date, interval, day) do
    Enum.find_value(1..480, fn step ->
      {year, month} = shift_months(date, step * interval)

      case Date.new(year, month, day) do
        {:ok, found} -> found
        {:error, _} -> nil
      end
    end)
  end

  defp next_year(%Date{year: year, month: month, day: day}, interval) do
    Enum.find_value(1..500, fn step ->
      case Date.new(year + step * interval, month, day) do
        {:ok, found} -> found
        {:error, _} -> nil
      end
    end)
  end

  defp shift_months(%Date{year: year, month: month}, add) do
    index = year * 12 + (month - 1) + add
    {div(index, 12), rem(index, 12) + 1}
  end

  defp add_months(date, add) do
    {year, month} = shift_months(date, add)
    last = Date.days_in_month(Date.new!(year, month, 1))
    Date.new!(year, month, min(date.day, last))
  end

  # Elapsed time jumps straight there, so an every-minute rule left for a
  # month does not step through each one.
  defp elapsed_after(from, now, seconds, ends_at) do
    steps = if DateTime.after?(from, now), do: 0, else: div(DateTime.diff(now, from), seconds)
    elapsed(DateTime.add(from, steps * seconds, :second), seconds, ends_at)
  end

  defp step_after(series, from, now, zone) do
    case next_slot(series, from, zone) do
      nil -> nil
      slot -> if DateTime.after?(slot, now), do: slot, else: step_after(series, slot, now, zone)
    end
  end

  defp elapsed(from, seconds, ends_at) do
    finish_instant(DateTime.add(from, seconds, :second), ends_at)
  end

  defp finish(nil, _time, _zone, _ends_at), do: nil

  defp finish(%Date{} = date, time, zone, ends_at) do
    finish_instant(Dates.from_local(date, time, :due_at, zone), ends_at)
  end

  defp finish_instant(slot, ends_at) do
    if after_end?(slot, ends_at), do: nil, else: slot
  end

  defp after_end?(_slot, nil), do: false

  defp after_end?(slot, %DateTime{} = ends_at) do
    DateTime.compare(slot, DateTime.truncate(ends_at, :second)) == :gt
  end

  defp shift_field(nil, _anchor_at, _slot, _zone), do: nil

  defp shift_field(%DateTime{} = date, nil, _slot, _zone), do: DateTime.truncate(date, :second)

  defp shift_field(%DateTime{} = date, %DateTime{} = anchor_at, slot, zone) do
    {anchor_day, _} = Dates.to_local(anchor_at, zone)
    {day, time} = Dates.to_local(date, zone)
    {slot_day, _} = Dates.to_local(slot, zone)
    moved = Date.add(slot_day, Date.diff(day, anchor_day))
    Dates.from_local(moved, time, :due_at, zone)
  end
end
