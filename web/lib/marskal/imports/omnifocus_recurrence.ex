defmodule Marskal.Imports.OmnifocusRecurrence do
  @moduledoc """
  Reads an OmniFocus repeat into a Marskal rule (ADR 0007, ADR 0013).

  OmniFocus stores the rule as an RFC 5545 RRULE in `repetition-rule`, and
  how it is scheduled beside it: `repetition-schedule-type` (`from-assigned`
  or `from-completion`) with `repetition-anchor-date` (`dateDue`,
  `dateToStart`, or `datePlanned`)
  and `catch-up-automatically`, or, in older backups, `repetition-method`
  (fixed, start-after-completion, due-after-completion). The oldest keep
  a short interval such as `@1w` in `repeat`.

  The parts Marskal has are read: FREQ, INTERVAL, weekdays for a weekly
  rule, days of the month and nth weekdays (with BYSETPOS for work and
  weekend days) for a monthly one, the same with BYMONTH for a yearly one,
  COUNT, UNTIL, and WKST.

  Where Marskal has no exact match, the closest rule is used and each
  difference is returned, for an import problem the user can check: a
  repeat after completion keeps its interval but not its days, and one
  that does not catch up does, as every regular Marskal series does.
  Anything else, such as BYHOUR or BYWEEKNO, is not read.
  """

  @freqs %{
    "MINUTELY" => "minutes",
    "HOURLY" => "hours",
    "DAILY" => "days",
    "WEEKLY" => "weeks",
    "MONTHLY" => "months",
    "YEARLY" => "years"
  }

  @short_units %{"h" => "hours", "d" => "days", "w" => "weeks", "m" => "months", "y" => "years"}

  @days %{
    "MO" => {1, "monday"},
    "TU" => {2, "tuesday"},
    "WE" => {3, "wednesday"},
    "TH" => {4, "thursday"},
    "FR" => {5, "friday"},
    "SA" => {6, "saturday"},
    "SU" => {7, "sunday"}
  }

  @work_days ~w(FR MO TH TU WE)
  @weekend_days ~w(SA SU)
  @known ~w(FREQ INTERVAL BYDAY BYMONTHDAY BYMONTH BYSETPOS COUNT UNTIL WKST)

  @doc """
  The rule for a parsed OmniFocus task row, as series attrs, and the
  differences from OmniFocus's own: `{:ok, rule, changes}`.
  `{:undated, anchor}` when the rule reads but the row lacks the date it
  would move, and `:error` when there is no repeat or it cannot be read.
  """
  def read(row) do
    with text when is_binary(text) and text != "" <- row["repeat"],
         {:ok, parts} <- parts(text),
         {:ok, mode} <- mode(row),
         {:ok, anchor} <- anchor(row, mode),
         {:ok, rule} <- rule(parts),
         true <- dated?(row, anchor) || {:undated, anchor} do
      {rule, changes} = fit(rule, mode, row)
      {:ok, Map.merge(rule, %{"mode" => mode, "anchor" => anchor}), changes}
    else
      {:undated, _anchor} = undated -> undated
      _ -> :error
    end
  end

  ## The RRULE

  defp parts(text) do
    text = text |> String.trim() |> String.replace_prefix("RRULE:", "")

    case Regex.run(~r/\A[@~+]?(\d+)\s*([hdwmy])\z/i, text) do
      [_, count, unit] ->
        {:ok, %{"FREQ" => {:short, @short_units[String.downcase(unit)]}, "INTERVAL" => count}}

      nil ->
        with {:ok, pairs} <- all(String.split(text, ";", trim: true), &part/1),
             do: {:ok, Map.new(pairs)}
    end
  end

  defp part(text) do
    case String.split(text, "=", parts: 2) do
      [key, value] when key in @known -> {:ok, {key, value}}
      _ -> :error
    end
  end

  defp rule(%{"FREQ" => freq} = parts) do
    with {:ok, frequency} <- frequency(freq),
         {:ok, interval} <- positive(Map.get(parts, "INTERVAL", "1")),
         {:ok, days} <- days(frequency, parts),
         {:ok, ends} <- ends(parts),
         {:ok, week} <- week_start(parts["WKST"]) do
      {:ok,
       %{"frequency" => frequency, "interval" => interval}
       |> Map.merge(days)
       |> Map.merge(ends)
       |> Map.merge(week)}
    end
  end

  defp rule(_parts), do: :error

  # Without WKST the series takes the user's week start.
  defp week_start(nil), do: {:ok, %{}}

  defp week_start(code) do
    case @days[code] do
      {number, _name} -> {:ok, %{"week_start" => number}}
      nil -> :error
    end
  end

  defp frequency({:short, unit}), do: {:ok, unit}
  defp frequency(freq), do: Map.fetch(@freqs, freq)

  defp days("weeks", parts) do
    with {days, nil, nil, nil} <-
           {list(parts["BYDAY"]), parts["BYMONTHDAY"], parts["BYMONTH"], parts["BYSETPOS"]},
         {:ok, numbers} <- all(days, &weekday_number/1) do
      {:ok, %{"weekdays" => Enum.sort(numbers), "on_days" => []}}
    else
      _ -> :error
    end
  end

  defp days("months", parts) do
    with nil <- parts["BYMONTH"],
         {:ok, rows} <- month_rows(parts) do
      {:ok, %{"weekdays" => [], "on_days" => rows}}
    else
      _ -> :error
    end
  end

  defp days("years", parts) do
    months = list(parts["BYMONTH"])

    cond do
      months == [] and is_nil(parts["BYDAY"]) and is_nil(parts["BYMONTHDAY"]) ->
        {:ok, %{"weekdays" => [], "on_days" => []}}

      months == [] ->
        :error

      true ->
        with {:ok, months} <- all(months, &month/1),
             {:ok, rows} <- month_rows(parts),
             true <- rows != [] do
          {:ok,
           %{
             "weekdays" => [],
             "on_days" => for(month <- months, row <- rows, do: "#{month}:#{row}")
           }}
        else
          _ -> :error
        end
    end
  end

  defp days(_frequency, parts) do
    if Enum.any?(~w(BYDAY BYMONTHDAY BYMONTH BYSETPOS), &Map.has_key?(parts, &1)),
      do: :error,
      else: {:ok, %{"weekdays" => [], "on_days" => []}}
  end

  # A month's rows: its calendar days, then its nth weekdays, or one day
  # kind picked by BYSETPOS.
  defp month_rows(parts) do
    with {:ok, calendar} <- all(list(parts["BYMONTHDAY"]), &calendar_day/1),
         {:ok, weekdays} <- weekday_rows(list(parts["BYDAY"]), parts["BYSETPOS"]) do
      {:ok, calendar ++ weekdays}
    end
  end

  defp calendar_day(text) do
    case Integer.parse(text) do
      {day, ""} when day in 1..31 or day in -5..-1//1 -> {:ok, "#{day}:day"}
      _ -> :error
    end
  end

  defp weekday_rows([], nil), do: {:ok, []}

  defp weekday_rows(days, nil), do: all(days, &nth_weekday/1)

  defp weekday_rows(days, position) do
    kind =
      case Enum.sort(days) do
        @work_days -> {"work_day", 23}
        @weekend_days -> {"weekend_day", 10}
        [code] when is_map_key(@days, code) -> {elem(@days[code], 1), 5}
        _ -> nil
      end

    with {name, most} <- kind,
         {:ok, rows} <- all(list(position), &ordinal(&1, most)) do
      {:ok, Enum.map(rows, &"#{&1}:#{name}")}
    else
      _ -> :error
    end
  end

  defp weekday_number(code) do
    case @days[code] do
      {number, _name} -> {:ok, number}
      nil -> :error
    end
  end

  # An nth weekday, such as 2TU or -1FR.
  defp nth_weekday(text) do
    with [_, ordinal, code] <- Regex.run(~r/\A([+-]?\d)([A-Z]{2})\z/, text),
         {_number, name} <- @days[code],
         {:ok, ordinal} <- ordinal(ordinal, 5) do
      {:ok, "#{ordinal}:#{name}"}
    else
      _ -> :error
    end
  end

  defp ordinal(text, most) do
    case Integer.parse(String.trim_leading(text, "+")) do
      {n, ""} when n in 1..most//1 or n in -5..-1//1 -> {:ok, n}
      _ -> :error
    end
  end

  defp month(text) do
    case Integer.parse(text) do
      {month, ""} when month in 1..12 -> {:ok, month}
      _ -> :error
    end
  end

  defp ends(parts) do
    with {:ok, count} <- optional(parts["COUNT"], &positive/1),
         {:ok, until} <- optional(parts["UNTIL"], &until/1) do
      {:ok, %{"end_count" => count, "ends_at" => until}}
    end
  end

  # UNTIL is a date or a UTC date-time. A date ends at the end of that day.
  defp until(text) do
    case Regex.run(~r/\A(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})Z?)?\z/, text) do
      [_, y, m, d] -> datetime(y, m, d, "23", "59", "59")
      [_, y, m, d, hh, mm, ss] -> datetime(y, m, d, hh, mm, ss)
      _ -> :error
    end
  end

  defp datetime(y, m, d, hh, mm, ss) do
    case NaiveDateTime.from_iso8601("#{y}-#{m}-#{d}T#{hh}:#{mm}:#{ss}") do
      {:ok, naive} -> {:ok, naive |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()}
      _ -> :error
    end
  end

  ## Scheduling

  defp mode(row) do
    case {row["repeat_schedule"], row["repeat_method"]} do
      {"from-completion", _} ->
        {:ok, "on_completion"}

      {"from-assigned", _} ->
        {:ok, "regular"}

      {nil, method} when method in ["start-after-completion", "due-after-completion"] ->
        {:ok, "on_completion"}

      {nil, method} when method in [nil, "fixed"] ->
        {:ok, "regular"}

      _ ->
        :error
    end
  end

  defp anchor(row, _mode) do
    case {row["repeat_anchor"], row["repeat_method"]} do
      {"dateDue", _} -> {:ok, "due"}
      {"dateToStart", _} -> {:ok, "defer"}
      {"datePlanned", _} -> {:ok, "planned"}
      {nil, "start-after-completion"} -> {:ok, "defer"}
      {nil, "due-after-completion"} -> {:ok, "due"}
      {nil, _fixed} -> {:ok, first_dated(row)}
      _ -> :error
    end
  end

  # A fixed repeat moves the dates the task has; Due first, as OmniFocus
  # shows it.
  defp first_dated(row) do
    cond do
      present?(row["due"]) -> "due"
      present?(row["start"]) -> "defer"
      true -> "planned"
    end
  end

  defp dated?(row, "due"), do: present?(row["due"])
  defp dated?(row, "defer"), do: present?(row["start"])
  defp dated?(row, "planned"), do: present?(row["planned"])

  # The closest Marskal rule, and what it does differently.
  defp fit(rule, "on_completion", _row) do
    if rule["weekdays"] == [] and rule["on_days"] == [] do
      {rule, []}
    else
      {%{rule | "weekdays" => [], "on_days" => []},
       ["repeats after completion without its days, which Marskal does not limit there"]}
    end
  end

  defp fit(rule, "regular", %{"repeat_catch_up" => "false"}),
    do: {rule, ["skips dates that have passed, where OmniFocus did not catch up"]}

  defp fit(rule, "regular", _row), do: {rule, []}

  ## Helpers

  defp list(nil), do: []
  defp list(text), do: String.split(text, ",", trim: true)

  defp all(items, fun) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      :error -> :error
    end
  end

  defp optional(nil, _fun), do: {:ok, nil}
  defp optional(value, fun), do: fun.(value)

  defp positive(text) do
    case Integer.parse(text) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp present?(value), do: is_binary(value) and value != ""
end
