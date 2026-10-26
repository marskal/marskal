defmodule Marskal.DateFormat do
  @moduledoc """
  Dates and times as the user reads them, in their locale (ADR 0027).

  The locale sets the order of day and month, the clock, and the
  separators. The words are English, except in `da`, whose month and
  weekday names are Danish. Each function takes the locale from
  `Marskal.Cldr.get_locale/0` unless `locale:` is given. A LiveView or
  request sets it from the user's preference (`put_locale/1`); code with no
  request, such as a notification, passes it.

  Times are formatted as given: shift a `DateTime` to the user's zone first.
  """

  @days %{
    weekday: :E,
    day_month: :MMMd,
    day_month_year: :yMMMd,
    long: :MMMMEEEEd,
    long_year: :yMMMMEEEEd
  }

  @doc "Formats with the user's locale from now on in this process."
  def put_locale(%Marskal.Accounts.User{} = user),
    do: Marskal.Cldr.put_locale(Marskal.Accounts.locale(user))

  @doc """
  A day: `:weekday` ("Sun"), `:day_month` ("11 Oct"), `:day_month_year`
  ("11 Oct 2026"), `:long` ("Sunday, 11 October"), or `:long_year`.
  """
  def date(date, style, opts \\ []) when is_map_key(@days, style),
    do: Marskal.Cldr.Date.to_string!(date, format: Map.fetch!(@days, style), locale: locale(opts))

  @doc ~S(A time of day on the locale's clock: "16:30", "16.30", or "4:30 PM".)
  def time(time, opts \\ []),
    do: Marskal.Cldr.Time.to_string!(time, format: :jm, locale: locale(opts))

  @doc "A day and a time: \"11 Oct 2026, 16:30\"."
  def date_time(datetime, opts \\ []) do
    Marskal.Cldr.DateTime.to_string!(datetime,
      date_format: :medium,
      time_format: :short,
      locale: locale(opts)
    )
  end

  @doc """
  The order the locale writes a numeric date in: `:dmy` ("22/11/2033"),
  `:mdy` ("11/22/33"), or `:ymd` ("2033-11-22").
  """
  def numeric_order(opts \\ []) do
    text = Marskal.Cldr.Date.to_string!(~D[2033-11-22], format: :yMd, locale: locale(opts))
    [day, month, year] = for part <- ["22", "11", "33"], do: :binary.match(text, part)

    cond do
      year < month -> :ymd
      month < day -> :mdy
      true -> :dmy
    end
  end

  @doc """
  The order the locale writes a day and month in, without a year: `:dm`
  ("22/11") or `:md` ("11/22"). A year-first locale may write either.
  """
  def day_month_order(opts \\ []) do
    text = Marskal.Cldr.Date.to_string!(~D[2033-11-22], format: :Md, locale: locale(opts))
    if :binary.match(text, "22") < :binary.match(text, "11"), do: :dm, else: :md
  end

  @doc "The locales a user can pick, each with the region its conventions come from."
  def locales do
    Marskal.Cldr.known_locale_names()
    |> Enum.map(&{to_string(&1), region(to_string(&1))})
    |> Enum.sort_by(fn {_name, region} -> region end)
  end

  defp locale(opts), do: Keyword.get_lazy(opts, :locale, &Marskal.Cldr.get_locale/0)

  @regions %{
    "da" => "Danish",
    "en" => "United States",
    "en-150" => "Europe",
    "en-AT" => "Austria",
    "en-AU" => "Australia",
    "en-BE" => "Belgium",
    "en-CA" => "Canada",
    "en-CH" => "Switzerland",
    "en-DE" => "Germany",
    "en-DK" => "Denmark",
    "en-ES" => "Spain",
    "en-FI" => "Finland",
    "en-FR" => "France",
    "en-GB" => "United Kingdom",
    "en-IE" => "Ireland",
    "en-IN" => "India",
    "en-IT" => "Italy",
    "en-NL" => "Netherlands",
    "en-NO" => "Norway",
    "en-NZ" => "New Zealand",
    "en-PL" => "Poland",
    "en-SE" => "Sweden",
    "en-ZA" => "South Africa"
  }

  defp region(name), do: Map.get(@regions, name, name)
end
