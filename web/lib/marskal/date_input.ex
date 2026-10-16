defmodule Marskal.DateInput do
  @moduledoc """
  A day, and maybe a time, as a person types it (ADR 0032): "tom", "fri",
  "1w", "24/12", "24 dec 14:00", "i morgen kl 9". The words are English and
  Danish, whatever the locale.

  Pure: the caller passes now on the user's wall clock, the first day of
  their week (1 = Monday … 7 = Sunday), and the order their locale writes a
  numeric date in. A day with no time read leaves the time `nil`, for the
  field's default (`Marskal.Dates.default_time/1`). The Rust client library
  must read the same way; both run `sync/fixtures/date_input.json`.
  """

  @type order :: :dmy | :mdy | :ymd
  @type result :: {:ok, Date.t(), Time.t() | nil} | :blank | :error

  @today ~w(today tod idag)
  @tomorrow ~w(tomorrow tom tmr tmrw imorgen)
  @yesterday ~w(yesterday igår)
  @now ~w(now nu)
  @next ~w(next næste)
  @within ~w(in om)
  @clock_markers ~w(at kl kl. klokken @)

  @weekdays %{
    1 => ~w(mon monday man mandag),
    2 => ~w(tue tues tuesday tir tirs tirsdag),
    3 => ~w(wed weds wednesday ons onsdag),
    4 => ~w(thu thur thurs thursday tor tors torsdag),
    5 => ~w(fri friday fre fredag),
    6 => ~w(sat saturday lør lørdag),
    7 => ~w(sun sunday søn søndag)
  }

  @months %{
    1 => ~w(jan january januar),
    2 => ~w(feb february februar),
    3 => ~w(mar march marts),
    4 => ~w(apr april),
    5 => ~w(may maj),
    6 => ~w(jun june juni),
    7 => ~w(jul july juli),
    8 => ~w(aug august),
    9 => ~w(sep sept september),
    10 => ~w(oct october okt oktober),
    11 => ~w(nov november),
    12 => ~w(dec december)
  }

  @units %{
    day: ~w(d day days dag dage),
    week: ~w(w wk wks week weeks uge uger),
    month: ~w(m mo mos month months md mdr måned måneder),
    year: ~w(y yr yrs year years år),
    hour: ~w(h hr hrs hour hours t time timer),
    minute: ~w(min mins minute minutes minut minutter)
  }

  @weekday_names for {n, names} <- @weekdays, name <- names, into: %{}, do: {name, n}
  @month_names for {n, names} <- @months, name <- names, into: %{}, do: {name, n}
  @unit_names for {unit, names} <- @units, name <- names, into: %{}, do: {name, unit}

  @doc """
  Reads `text`. `now` is a `NaiveDateTime` on the user's wall clock;
  `opts` are `week_start:` (1..7) and `order:` (`:dmy`, `:mdy`, `:ymd`).

  Blank text is `:blank`, which clears the field.
  """
  @spec parse(String.t(), NaiveDateTime.t(), keyword()) :: result()
  def parse(text, %NaiveDateTime{} = now, opts) do
    ctx = %{
      now: now,
      today: NaiveDateTime.to_date(now),
      week_start: Keyword.fetch!(opts, :week_start),
      order: Keyword.fetch!(opts, :order)
    }

    case words(text) do
      [] -> :blank
      words -> read(words, ctx)
    end
  end

  defp words(text) do
    case :unicode.characters_to_nfc_binary(text) do
      text when is_binary(text) ->
        text |> String.downcase() |> String.replace(",", " ") |> String.split()

      _ ->
        []
    end
  end

  defp read(words, ctx) do
    {day_words, time} = split_time(words)

    case {day(day_words, ctx), time} do
      {:none, nil} -> :error
      {:none, time} -> {:ok, ctx.today, time}
      {{:ok, date}, time} -> {:ok, date, time}
      {{:ok, date, time}, nil} -> {:ok, date, time}
      _ -> :error
    end
  end

  ## Time of day

  # A time at the end ("fri 14:00", "tom kl 9", "24/12 2pm"), else at the
  # start ("14:00 fri"). A dotted time ("14.30") is read only after a day,
  # since alone it is a date.
  defp split_time(words) do
    with :none <- time_at_end(words),
         :none <- time_at_start(words) do
      {words, nil}
    end
  end

  defp time_at_end(words) do
    case Enum.reverse(words) do
      [token, marker | rest] when marker in @clock_markers ->
        found(clock(token, bare: true, dot: true), Enum.reverse(rest))

      [ampm, token | rest] when ampm in ~w(am pm) ->
        found(clock(token <> ampm, []), Enum.reverse(rest))

      ["@" <> token | rest] ->
        found(clock(token, bare: true, dot: true), Enum.reverse(rest))

      [token | rest] ->
        found(clock(token, dot: rest != []), Enum.reverse(rest))

      [] ->
        :none
    end
  end

  defp time_at_start(words) do
    case words do
      [marker, token | rest] when marker in @clock_markers ->
        found(clock(token, bare: true, dot: true), rest)

      [token, ampm | rest] when ampm in ~w(am pm) ->
        found(clock(token <> ampm, []), rest)

      ["@" <> token | rest] ->
        found(clock(token, bare: true, dot: true), rest)

      [token | rest] ->
        found(clock(token, []), rest)
    end
  end

  defp found(nil, _rest), do: :none
  defp found(time, rest), do: {rest, time}

  # "14:30", "2pm", "2:30pm"; "14.30" with `dot:`, "14" with `bare:`.
  defp clock(token, opts) do
    case Regex.run(~r/^(\d{1,2})(?:([:.])(\d{2}))?(am|pm)?$/, token) do
      [_, hour] -> if opts[:bare], do: time(int(hour), 0)
      [_, hour, sep, minute] -> if separated?(sep, opts), do: time(int(hour), int(minute))
      [_, hour, "", "", ampm] -> half_day(int(hour), 0, ampm)
      [_, hour, _sep, minute, ampm] -> half_day(int(hour), int(minute), ampm)
      nil -> nil
    end
  end

  defp separated?(":", _opts), do: true
  defp separated?(".", opts), do: opts[:dot] == true

  defp half_day(hour, minute, ampm) when hour in 1..12 do
    hour = rem(hour, 12) + if(ampm == "pm", do: 12, else: 0)
    time(hour, minute)
  end

  defp half_day(_hour, _minute, _ampm), do: nil

  defp time(hour, minute) do
    case Time.new(hour, minute, 0) do
      {:ok, time} -> time
      {:error, _} -> nil
    end
  end

  ## The day

  defp day([], _ctx), do: :none
  defp day([word], ctx) when word in @now, do: {:ok, ctx.today, minute(ctx.now)}
  defp day([word], ctx) when word in @today, do: {:ok, ctx.today}
  defp day(["i", "dag"], ctx), do: {:ok, ctx.today}
  defp day([word], ctx) when word in @tomorrow, do: {:ok, Date.add(ctx.today, 1)}
  defp day(["i", "morgen"], ctx), do: {:ok, Date.add(ctx.today, 1)}
  defp day([word], ctx) when word in @yesterday, do: {:ok, Date.add(ctx.today, -1)}
  defp day(["i", "går"], ctx), do: {:ok, Date.add(ctx.today, -1)}
  defp day(["overmorgen"], ctx), do: {:ok, Date.add(ctx.today, 2)}
  defp day(["i", "overmorgen"], ctx), do: {:ok, Date.add(ctx.today, 2)}
  defp day([word | rest], ctx) when word in @within and rest != [], do: relative(rest, ctx)

  defp day([next, word], ctx) when next in @next do
    next_week = Date.add(week_start(ctx.today, ctx.week_start), 7)

    cond do
      word in ~w(week uge) ->
        {:ok, next_week}

      word in ~w(month måned) ->
        {:ok, ctx.today |> Date.beginning_of_month() |> Date.shift(month: 1)}

      word in ~w(year år) ->
        {:ok, Date.new!(ctx.today.year + 1, 1, 1)}

      weekday = weekday(word) ->
        {:ok, Date.add(next_week, Integer.mod(weekday - ctx.week_start, 7))}

      true ->
        :error
    end
  end

  defp day([word | rest] = words, ctx) do
    weekday = weekday(word)

    cond do
      weekday && rest == [] -> {:ok, next_weekday(ctx.today, weekday)}
      weekday -> on_weekday(date(rest, ctx), weekday)
      true -> with :error <- date(words, ctx), do: relative(words, ctx)
    end
  end

  # "fri 23 oct": the weekday must be that day's.
  defp on_weekday({:ok, date}, weekday) do
    if Date.day_of_week(date) == weekday, do: {:ok, date}, else: :error
  end

  defp on_weekday(:error, _weekday), do: :error

  # The weekday after today, a week on when today is that weekday.
  defp next_weekday(today, weekday),
    do: Date.add(today, Integer.mod(weekday - Date.day_of_week(today) - 1, 7) + 1)

  defp week_start(date, first),
    do: Date.add(date, -Integer.mod(Date.day_of_week(date) - first, 7))

  # "1w", "+3d", "-1d", "2 weeks", "in 3h", "om 2 dage".
  defp relative(words, ctx) do
    with [_, sign, count, unit] <- Regex.run(~r/^([+-]?)(\d+)(\D+)$/u, Enum.join(words)),
         {:ok, unit} <- Map.fetch(@unit_names, unit) do
      count = if sign == "-", do: -int(count), else: int(count)
      step(unit, count, ctx)
    else
      _ -> :error
    end
  end

  defp step(:hour, count, ctx), do: at(NaiveDateTime.add(ctx.now, count, :hour))
  defp step(:minute, count, ctx), do: at(NaiveDateTime.add(ctx.now, count, :minute))
  defp step(unit, count, ctx), do: {:ok, Date.shift(ctx.today, [{unit, count}])}

  defp at(datetime), do: {:ok, NaiveDateTime.to_date(datetime), minute(datetime)}

  defp minute(datetime),
    do: datetime |> NaiveDateTime.to_time() |> Map.merge(%{second: 0, microsecond: {0, 0}})

  ## Dates

  # "2026-12-24", "24/12", "24.12.26", "24", "24th", "24 dec", "dec 24 2026".
  defp date([token], ctx) do
    cond do
      day = ordinal(token) -> day_of_month(day, ctx.today)
      String.match?(token, ~r/^\d[\d.\/-]*\d\.?$/) -> numeric(token, ctx)
      true -> :error
    end
  end

  defp date([a, b], ctx) do
    case named(a, b) do
      {month, day} -> upcoming(month, day, ctx.today)
      nil -> :error
    end
  end

  defp date([a, b, year], _ctx) do
    case {named(a, b), year(year)} do
      {{month, day}, year} when is_integer(year) -> exact(year, month, day)
      _ -> :error
    end
  end

  defp date(_words, _ctx), do: :error

  # "24 dec" or "dec 24", as {month, day}.
  defp named(a, b) do
    case {ordinal(a), month(b), month(a), ordinal(b)} do
      {day, month, _, _} when is_integer(day) and is_integer(month) -> {month, day}
      {_, _, month, day} when is_integer(day) and is_integer(month) -> {month, day}
      _ -> nil
    end
  end

  # Digits split by one kind of separator. Four digits first is year, month,
  # day; otherwise the locale's order, and a two-digit year is this century.
  defp numeric(token, ctx) do
    token = String.trim_trailing(token, ".")
    separators = token |> String.replace(~r/\d/, "") |> String.graphemes() |> Enum.uniq()
    parts = String.split(token, ["/", ".", "-"])

    case {separators, Enum.map(parts, &byte_size/1)} do
      {[_], [4, m, d]} when m <= 2 and d <= 2 ->
        numeric_date(:ymd, Enum.map(parts, &int/1), ctx)

      {[_], [a, b]} when a <= 2 and b <= 2 ->
        numeric_date(ctx.order, Enum.map(parts, &int/1), ctx)

      {[_], [a, b, c]} when a <= 2 and b <= 2 and c in [2, 4] ->
        numeric_date(ctx.order, Enum.map(parts, &int/1), ctx)

      _ ->
        :error
    end
  end

  defp numeric_date(:dmy, [day, month], ctx), do: upcoming(month, day, ctx.today)
  defp numeric_date(_order, [month, day], ctx), do: upcoming(month, day, ctx.today)
  defp numeric_date(:dmy, [day, month, year], _ctx), do: exact(century(year), month, day)
  defp numeric_date(:mdy, [month, day, year], _ctx), do: exact(century(year), month, day)
  defp numeric_date(:ymd, [year, month, day], _ctx), do: exact(century(year), month, day)

  defp century(year) when year < 100, do: 2000 + year
  defp century(year), do: year

  # The next day with this day of the month, today included.
  defp day_of_month(day, today) when day in 1..31 do
    Enum.find_value(0..12, :error, fn months ->
      first = today |> Date.beginning_of_month() |> Date.shift(month: months)
      from_today(first.year, first.month, day, today)
    end)
  end

  defp day_of_month(_day, _today), do: :error

  # This month and day, this year or the next with it, today included.
  defp upcoming(month, day, today) do
    Enum.find_value(today.year..(today.year + 8), :error, &from_today(&1, month, day, today))
  end

  defp from_today(year, month, day, today) do
    with {:ok, date} <- Date.new(year, month, day),
         false <- Date.before?(date, today) do
      {:ok, date}
    else
      _ -> nil
    end
  end

  defp exact(year, month, day) do
    case Date.new(year, month, day) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> :error
    end
  end

  ## Words

  defp weekday(word), do: Map.get(@weekday_names, String.trim_trailing(word, "."))
  defp month(word), do: Map.get(@month_names, String.trim_trailing(word, "."))

  # "24", "24.", "24th", "1st", "2nd", "3rd".
  defp ordinal(token) do
    case Regex.run(~r/^(\d{1,2})(?:\.|st|nd|rd|th)?$/, token) do
      [_, day] -> int(day)
      nil -> nil
    end
  end

  defp year(token) do
    if String.match?(token, ~r/^(\d{2}|\d{4})$/), do: century(int(token))
  end

  defp int(digits), do: String.to_integer(digits)
end
