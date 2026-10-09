defmodule Marskal.Imports.TodoistRecurrence do
  @moduledoc """
  Reads a Todoist repeat, as Todoist gives it (`due.string`, the words the
  user typed), into a Marskal rule (ADR 0007, ADR 0013).

  The common forms are read:

    * `daily`, `weekly`, `monthly`, `yearly`, `hourly`
    * `every day`, `every 3 weeks`, `every other month`, `every 2 hours`
    * weekdays: `every mon, fri`, `every other tuesday`, `every weekday`,
      `every weekend`, `every 2 weeks on mon and thu`
    * days of the month: `every 15th`, `every 1st and 15th`,
      `every last day`, `every 2nd tuesday`, `every last workday`,
      `every month on the 15th`
    * days of the year: `every jan 15`, `every 15 january`,
      `every year on mar 1st`
    * `every!` repeats after completion: `every! 3 days`
    * a trailing time, `at 9am` or `at 17:00`, is dropped: the task's own
      date carries it.

  Anything else, such as `every other tuesday starting next month` or
  `every 3rd workday until june`, is not read, and stays an import problem
  for the user to set up. Free-form text could be read later, by Todoist's
  own parser through its API or by a language model, but is not yet.

  The rule moves the Planned date, which is where a Todoist due date goes.
  """

  @units %{
    "minute" => :minutes,
    "minutes" => :minutes,
    "min" => :minutes,
    "mins" => :minutes,
    "hour" => :hours,
    "hours" => :hours,
    "day" => :days,
    "days" => :days,
    "week" => :weeks,
    "weeks" => :weeks,
    "month" => :months,
    "months" => :months,
    "year" => :years,
    "years" => :years
  }

  @alone %{
    "hourly" => :hours,
    "daily" => :days,
    "weekly" => :weeks,
    "monthly" => :months,
    "yearly" => :years,
    "annually" => :years
  }

  @weekdays %{
    "mon" => 1,
    "monday" => 1,
    "tue" => 2,
    "tues" => 2,
    "tuesday" => 2,
    "wed" => 3,
    "weds" => 3,
    "wednesday" => 3,
    "thu" => 4,
    "thur" => 4,
    "thurs" => 4,
    "thursday" => 4,
    "fri" => 5,
    "friday" => 5,
    "sat" => 6,
    "saturday" => 6,
    "sun" => 7,
    "sunday" => 7
  }

  @kinds %{
    1 => "monday",
    2 => "tuesday",
    3 => "wednesday",
    4 => "thursday",
    5 => "friday",
    6 => "saturday",
    7 => "sunday"
  }

  @ordinals %{
    "first" => 1,
    "1st" => 1,
    "second" => 2,
    "2nd" => 2,
    "third" => 3,
    "3rd" => 3,
    "fourth" => 4,
    "4th" => 4,
    "fifth" => 5,
    "5th" => 5,
    "last" => -1
  }

  @months %{
    "jan" => 1,
    "january" => 1,
    "feb" => 2,
    "february" => 2,
    "mar" => 3,
    "march" => 3,
    "apr" => 4,
    "april" => 4,
    "may" => 5,
    "jun" => 6,
    "june" => 6,
    "jul" => 7,
    "july" => 7,
    "aug" => 8,
    "august" => 8,
    "sep" => 9,
    "sept" => 9,
    "september" => 9,
    "oct" => 10,
    "october" => 10,
    "nov" => 11,
    "november" => 11,
    "dec" => 12,
    "december" => 12
  }

  @doc """
  The series attrs `text` means, or `:error` when it is not one of the
  forms read.
  """
  def parse(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.replace(~r/ (at|@) [0-9:.apm ]+$/, "")
    |> read()
  end

  def parse(_text), do: :error

  defp read(text) when is_map_key(@alone, text), do: rule(:regular, 1, @alone[text], [], [])
  defp read("every! " <> rest), do: body(rest, :on_completion)
  defp read("every " <> rest), do: body(rest, :regular)
  defp read(_text), do: :error

  # A leading number is a count, unless the rest only reads with it as a
  # day, as in "every 15 january".
  defp body(text, mode) do
    case counted(text, mode) do
      :error -> days(mode, 1, text)
      rule -> rule
    end
  end

  defp counted(text, mode) do
    {interval, rest} = count(text)

    case String.split(rest, " on ", parts: 2) do
      [unit] when is_map_key(@units, unit) ->
        rule(mode, interval, @units[unit], [], [])

      [unit, days] when is_map_key(@units, unit) ->
        on(mode, interval, @units[unit], String.replace_prefix(days, "the ", ""))

      _ ->
        days(mode, interval, rest)
    end
  end

  # "other" is every second one; a number is how many.
  defp count("other " <> rest), do: {2, rest}

  defp count(text) do
    case Integer.parse(text) do
      {n, " " <> rest} when n > 0 -> {n, rest}
      _ -> {1, text}
    end
  end

  # "every 2 weeks on mon", "every month on the 15th", "every year on jan 15".
  defp on(mode, interval, frequency, days) do
    with {found, rows} <- items(days),
         true <- found == kind_of(frequency) do
      rule(mode, interval, frequency, weekdays(found, rows), on_days(found, rows))
    else
      _ -> :error
    end
  end

  # "every mon, fri", "every other tuesday", "every 15th", "every jan 15".
  defp days(mode, interval, text) do
    case items(text) do
      {:weekdays, rows} -> rule(mode, interval, :weeks, rows, [])
      {:month_days, rows} -> rule(mode, interval, :months, [], rows)
      {:year_days, rows} -> rule(mode, interval, :years, [], rows)
      :error -> :error
    end
  end

  defp kind_of(:weeks), do: :weekdays
  defp kind_of(:months), do: :month_days
  defp kind_of(:years), do: :year_days
  defp kind_of(_frequency), do: nil

  defp weekdays(:weekdays, rows), do: rows
  defp weekdays(_found, _rows), do: []

  defp on_days(:weekdays, _rows), do: []
  defp on_days(_found, rows), do: rows

  # A list of days, all of one kind, joined by commas or "and".
  defp items(text) do
    parsed =
      text
      |> String.split(~r/\s*(,|\band\b)\s*/, trim: true)
      |> Enum.map(&item/1)

    case parsed |> Enum.map(&elem(&1, 0)) |> Enum.uniq() do
      [kind] when kind in [:weekdays, :month_days, :year_days] ->
        {kind, parsed |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq()}

      _ ->
        :error
    end
  end

  defp item(word) when is_map_key(@weekdays, word), do: {:weekdays, [@weekdays[word]]}

  defp item(word) when word in ["weekday", "workday", "work day"],
    do: {:weekdays, [1, 2, 3, 4, 5]}

  defp item("weekend"), do: {:weekdays, [6, 7]}
  defp item("last day"), do: {:month_days, ["-1:day"]}

  defp item(text) do
    case String.split(text, " ") do
      [day] ->
        month_day(day)

      [ordinal, kind] when is_map_key(@ordinals, ordinal) ->
        nth(@ordinals[ordinal], kind)

      ["last", "work", "day"] ->
        {:month_days, ["-1:work_day"]}

      [ordinal, "work", "day"] when is_map_key(@ordinals, ordinal) ->
        {:month_days, ["#{@ordinals[ordinal]}:work_day"]}

      [first, second] ->
        year_day(first, second)

      _ ->
        {:error, []}
    end
  end

  defp month_day(day) do
    case day_number(day) do
      nil -> {:error, []}
      n -> {:month_days, ["#{n}:day"]}
    end
  end

  defp nth(ordinal, kind) when is_map_key(@weekdays, kind),
    do: {:month_days, ["#{ordinal}:#{@kinds[@weekdays[kind]]}"]}

  defp nth(ordinal, kind) when kind in ["workday", "weekday"],
    do: {:month_days, ["#{ordinal}:work_day"]}

  defp nth(ordinal, kind) when kind in ["weekend", "weekend day"],
    do: {:month_days, ["#{ordinal}:weekend_day"]}

  defp nth(-1, "day"), do: {:month_days, ["-1:day"]}
  defp nth(_ordinal, _kind), do: {:error, []}

  # "jan 15", "15 jan", "january 15th".
  defp year_day(first, second) do
    case {@months[first], day_number(second), @months[second], day_number(first)} do
      {month, day, _, _} when is_integer(month) and is_integer(day) ->
        {:year_days, ["#{month}:#{day}:day"]}

      {_, _, month, day} when is_integer(month) and is_integer(day) ->
        {:year_days, ["#{month}:#{day}:day"]}

      _ ->
        {:error, []}
    end
  end

  defp day_number(text) do
    case Integer.parse(text) do
      {n, suffix} when n in 1..31 and suffix in ["", "st", "nd", "rd", "th"] -> n
      _ -> nil
    end
  end

  # After completion is an interval, with no days (ADR 0007).
  defp rule(:on_completion, _interval, _frequency, weekdays, on_days)
       when weekdays != [] or on_days != [],
       do: :error

  defp rule(mode, interval, frequency, weekdays, on_days) do
    {:ok,
     %{
       "mode" => Atom.to_string(mode),
       "anchor" => "planned",
       "interval" => interval,
       "frequency" => Atom.to_string(frequency),
       "weekdays" => Enum.sort(weekdays),
       "on_days" => on_days
     }}
  end
end
