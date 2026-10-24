defmodule Marskal.DateInput do
  @moduledoc """
  A day, and maybe a time, as a person types it (ADR 0032): "tom", "fri",
  "1w", "24/12", "24 dec 14:00", and with a Danish locale "i morgen kl 9".
  English words are always read, and the words of the locale's language.

  Pure: the caller passes now on the user's wall clock, the first day of
  their week (1 = Monday … 7 = Sunday), and their locale's language and the
  orders it writes numeric dates in, with a year and without. A day with no time read leaves the time `nil`, for the
  field's default (`Marskal.Dates.default_time/1`). The Rust client library
  must read the same way; both run `sync/fixtures/date_input.json`.
  """

  @type order :: :dmy | :mdy | :ymd
  @type day_month :: :dm | :md

  # "tonight" is today at the `evening:` time, unless a time is typed with it.
  @evening ~T[19:00:00]
  @type result :: {:ok, Date.t(), Time.t() | nil} | :blank | :error

  # The words of each language. English is always read; another language's
  # words are read as well when the user's locale is in it. Phrases of more
  # than one word are matched whole. `clock` words come before a time ("at
  # 9"), `clock_after` words after it ("9 o'clock"), and `fillers` are
  # skipped wherever they are ("on fri").
  @languages %{
    "en" => %{
      days: %{
        0 => ~w(today tod),
        1 => ~w(tomorrow tom tmr tmrw),
        -1 => ~w(yesterday)
      },
      now: ~w(now),
      evening: ["tonight"],
      evening_words: ~w(evening night),
      next: ~w(next),
      within: ~w(in),
      clock: ~w(at @),
      clock_after: ~w(o'clock oclock),
      fillers: ~w(on),
      periods: %{week: ~w(week), month: ~w(month), year: ~w(year)},
      weekdays: %{
        1 => ~w(mon monday),
        2 => ~w(tue tues tuesday),
        3 => ~w(wed weds wednesday),
        4 => ~w(thu thur thurs thursday),
        5 => ~w(fri friday),
        6 => ~w(sat saturday),
        7 => ~w(sun sunday)
      },
      months: %{
        1 => ~w(jan january),
        2 => ~w(feb february),
        3 => ~w(mar march),
        4 => ~w(apr april),
        5 => ~w(may),
        6 => ~w(jun june),
        7 => ~w(jul july),
        8 => ~w(aug august),
        9 => ~w(sep sept september),
        10 => ~w(oct october),
        11 => ~w(nov november),
        12 => ~w(dec december)
      },
      units: %{
        day: ~w(d day days),
        week: ~w(w wk wks week weeks),
        month: ~w(m mo mos month months),
        year: ~w(y yr yrs year years),
        hour: ~w(h hr hrs hour hours),
        minute: ~w(min mins minute minutes)
      }
    },
    "da" => %{
      days: %{
        0 => ["i dag", "idag"],
        1 => ["i morgen", "imorgen"],
        2 => ["i overmorgen", "overmorgen"],
        -1 => ["i går", "igår"]
      },
      now: ~w(nu),
      evening: ["i aften", "iaften"],
      evening_words: ~w(aften),
      next: ~w(næste),
      within: ~w(om),
      clock: ~w(kl kl. klokken),
      clock_after: [],
      fillers: ~w(på den),
      periods: %{week: ~w(uge), month: ~w(måned), year: ~w(år)},
      weekdays: %{
        1 => ~w(man mandag),
        2 => ~w(tir tirs tirsdag),
        3 => ~w(ons onsdag),
        4 => ~w(tor tors torsdag),
        5 => ~w(fre fredag),
        6 => ~w(lør lørdag),
        7 => ~w(søn søndag)
      },
      months: %{
        1 => ~w(januar),
        2 => ~w(februar),
        3 => ~w(marts),
        5 => ~w(maj),
        6 => ~w(juni),
        7 => ~w(juli),
        10 => ~w(okt oktober)
      },
      units: %{
        day: ~w(dag dage),
        week: ~w(uge uger),
        month: ~w(md mdr måned måneder),
        year: ~w(år),
        hour: ~w(t time timer),
        minute: ~w(minut minutter)
      }
    }
  }

  # Each language's words, English's added, as word => meaning.
  @lexicons Map.new(@languages, fn {language, _} ->
              sources = Enum.uniq([@languages["en"], @languages[language]])

              lookup = fn key ->
                for source <- sources,
                    {meaning, words} <- source[key],
                    word <- words,
                    into: %{},
                    do: {word, meaning}
              end

              list = fn key -> Enum.flat_map(sources, & &1[key]) end

              {language,
               %{
                 days: lookup.(:days),
                 periods: lookup.(:periods),
                 weekdays: lookup.(:weekdays),
                 months: lookup.(:months),
                 units: lookup.(:units),
                 now: list.(:now),
                 evening: list.(:evening),
                 evening_words: list.(:evening_words),
                 next: list.(:next),
                 within: list.(:within),
                 clock: list.(:clock),
                 clock_after: list.(:clock_after),
                 fillers: list.(:fillers)
               }}
            end)

  @doc "The languages whose words are read besides English."
  def languages, do: @languages |> Map.keys() |> List.delete("en")

  @doc """
  Reads `text`. `now` is a `NaiveDateTime` on the user's wall clock.
  `opts` are `week_start:` (1..7), `order:` (`:dmy`, `:mdy`, `:ymd`) for a
  date with a year, `day_month:` (`:dm`, `:md`) for one without, by default
  day first when `order` is, and `language:`, the locale's language ("en"
  when not given or not known). A locale may write the two differently:
  Swedish English is "2033-11-22" and "22/11".
  `evening:` is the time "tonight" means, 19:00 when not given; the field
  being typed in sets it (`Marskal.Dates.evening_time/1`).

  Blank text is `:blank`, which clears the field; text of only filler
  words ("on") is an error.
  """
  @spec parse(String.t(), NaiveDateTime.t(), keyword()) :: result()
  def parse(text, %NaiveDateTime{} = now, opts) do
    ctx = %{
      now: now,
      today: NaiveDateTime.to_date(now),
      week_start: Keyword.fetch!(opts, :week_start),
      order: Keyword.fetch!(opts, :order),
      evening: Keyword.get(opts, :evening, @evening),
      day_month:
        Keyword.get_lazy(opts, :day_month, fn ->
          if opts[:order] == :dmy, do: :dm, else: :md
        end),
      words: Map.get(@lexicons, Keyword.get(opts, :language, "en"), @lexicons["en"])
    }

    case words(text) do
      [] -> :blank
      words -> words |> Enum.reject(&(&1 in ctx.words.fillers)) |> read(ctx)
    end
  end

  defp words(text) do
    case :unicode.characters_to_nfc_binary(text) do
      text when is_binary(text) ->
        text |> String.downcase() |> String.split(~r/[\s,]+/u, trim: true)

      _ ->
        []
    end
  end

  defp read(words, ctx) do
    {day_words, time} = split_time(words, ctx.words)

    case {day(day_words, ctx), time} do
      {:none, nil} -> :error
      {:none, time} -> {:ok, ctx.today, time}
      {{:ok, date}, time} -> {:ok, date, time}
      {{:ok, date, time}, nil} -> {:ok, date, time}
      {{:evening, date}, nil} -> {:ok, date, ctx.evening}
      {{:evening, date}, time} -> {:ok, date, time}
      _ -> :error
    end
  end

  ## Time of day

  # A time at the end ("fri 14:00", "tom kl 9", "24/12 2pm", "fri 9
  # o'clock"), else at the start ("14:00 fri"). A dotted time ("14.30") is
  # read only after a day, since alone it is a date.
  defp split_time(words, lexicon) do
    with {_, nil} <- time_at_end(words, lexicon),
         {_, nil} <- time_at_start(words, lexicon) do
      {words, nil}
    end
  end

  defp time_at_end(words, lexicon) do
    {rest, time} = clock_words(Enum.reverse(words), lexicon, true)
    {Enum.reverse(rest), time}
  end

  defp time_at_start(words, lexicon), do: clock_words(words, lexicon, false)

  # The time at the head of `words`, which are reversed when `at_end`.
  defp clock_words(words, lexicon, at_end) do
    case words do
      [first, second | rest] ->
        {marker, token} = if at_end, do: {second, first}, else: {first, second}
        {suffix, hour} = if at_end, do: {first, second}, else: {second, first}

        cond do
          marker in lexicon.clock -> found(clock(token, bare: true, dot: true), rest)
          suffix in ~w(am pm) -> found(clock(hour <> suffix, []), rest)
          suffix in lexicon.clock_after -> found(clock(hour, bare: true, dot: true), rest)
          true -> one_clock_word(words, at_end)
        end

      words ->
        one_clock_word(words, at_end)
    end
  end

  defp one_clock_word(["@" <> token | rest], _at_end),
    do: found(clock(token, bare: true, dot: true), rest)

  defp one_clock_word([token | rest], at_end),
    do: found(clock(token, dot: at_end and rest != []), rest)

  defp one_clock_word([], _at_end), do: {[], nil}

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

  defp day(words, ctx) do
    phrase = phrase(Enum.join(words, " "), ctx)
    {before, [last]} = Enum.split(words, -1)

    cond do
      phrase -> phrase
      last in ctx.words.evening_words -> evening(day(before, ctx), ctx)
      true -> named_day(words, ctx)
    end
  end

  # "tue evening", "tomorrow night", "i morgen aften": that day's evening.
  # Alone, the word is tonight.
  defp evening(:none, ctx), do: {:evening, ctx.today}
  defp evening({:ok, date}, _ctx), do: {:evening, date}
  defp evening(_day, _ctx), do: :error

  defp named_day([word | rest] = words, ctx) do
    cond do
      rest == [] and word in ctx.words.now -> {:ok, ctx.today, minute(ctx.now)}
      rest != [] and word in ctx.words.within -> relative(rest, ctx)
      match?([_], rest) and word in ctx.words.next -> next(hd(rest), ctx)
      true -> on_or_after(words, ctx)
    end
  end

  # "tomorrow", "i morgen", "tonight": a day named in words.
  defp phrase(phrase, ctx) do
    case Map.fetch(ctx.words.days, phrase) do
      {:ok, offset} -> {:ok, Date.add(ctx.today, offset)}
      :error -> if phrase in ctx.words.evening, do: {:evening, ctx.today}
    end
  end

  # A weekday, a date, a weekday and a date, or a step.
  defp on_or_after([word | rest] = words, ctx) do
    case {weekday(word, ctx), rest} do
      {nil, _} -> with :error <- date(words, ctx), do: relative(words, ctx)
      {weekday, []} -> {:ok, next_weekday(ctx.today, weekday)}
      {weekday, rest} -> on_weekday(date(rest, ctx), weekday)
    end
  end

  # "next fri", "next week": in the week after this one, by the week start.
  defp next(word, ctx) do
    next_week = Date.add(week_start(ctx.today, ctx.week_start), 7)

    case {Map.get(ctx.words.periods, word), weekday(word, ctx)} do
      {:week, _} -> {:ok, next_week}
      {:month, _} -> {:ok, ctx.today |> Date.beginning_of_month() |> Date.shift(month: 1)}
      {:year, _} -> {:ok, Date.new!(ctx.today.year + 1, 1, 1)}
      {nil, nil} -> :error
      {nil, weekday} -> {:ok, Date.add(next_week, Integer.mod(weekday - ctx.week_start, 7))}
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
         {:ok, unit} <- Map.fetch(ctx.words.units, unit) do
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
    case named(a, b, ctx) do
      {month, day} -> upcoming(month, day, ctx.today)
      nil -> :error
    end
  end

  defp date([a, b, year], ctx) do
    case {named(a, b, ctx), year(year)} do
      {{month, day}, year} when is_integer(year) -> exact(year, month, day)
      _ -> :error
    end
  end

  defp date(_words, _ctx), do: :error

  # "24 dec" or "dec 24", as {month, day}.
  defp named(a, b, ctx) do
    case {ordinal(a), month(b, ctx), month(a, ctx), ordinal(b)} do
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
        numeric_date(ctx.day_month, Enum.map(parts, &int/1), ctx)

      {[_], [a, b, c]} when a <= 2 and b <= 2 and c in [2, 4] ->
        numeric_date(ctx.order, Enum.map(parts, &int/1), ctx)

      _ ->
        :error
    end
  end

  defp numeric_date(:dm, [day, month], ctx), do: upcoming(month, day, ctx.today)
  defp numeric_date(:md, [month, day], ctx), do: upcoming(month, day, ctx.today)
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

  defp weekday(word, ctx), do: Map.get(ctx.words.weekdays, String.trim_trailing(word, "."))
  defp month(word, ctx), do: Map.get(ctx.words.months, String.trim_trailing(word, "."))

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
