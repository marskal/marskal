defmodule Marskal.ReviewInterval do
  @moduledoc """
  A review interval, a Postgres `interval` with date parts only (ADR 0026).

  It casts from a `Duration` or its ISO 8601 form, letters in either case,
  and is kept as Postgres keeps it: months and days. Weeks become days and
  twelve months a year, so `P2W` is `P14D` both in the change feed and on a
  pull.
  """

  use Ecto.Type

  def type, do: :duration

  def cast(%Duration{} = duration), do: {:ok, normalize(duration)}

  def cast(text) when is_binary(text) do
    case Duration.from_iso8601(String.upcase(String.trim(text))) do
      {:ok, duration} -> {:ok, normalize(duration)}
      {:error, _} -> :error
    end
  end

  def cast(_), do: :error

  def load(%Duration{} = duration), do: {:ok, normalize(duration)}
  def load(_), do: :error

  def dump(%Duration{} = duration), do: {:ok, duration}
  def dump(_), do: :error

  @doc "Whether the interval has date parts only, none negative, and is not zero."
  def valid?(%Duration{} = duration) do
    time = [duration.hour, duration.minute, duration.second, elem(duration.microsecond, 0)]
    date = [duration.year, duration.month, duration.week, duration.day]

    Enum.all?(time, &(&1 == 0)) and Enum.all?(date, &(&1 >= 0)) and Enum.any?(date, &(&1 > 0))
  end

  @doc "Validates `field` as a review interval. The database checks the same."
  def validate(changeset, field) do
    Ecto.Changeset.validate_change(changeset, field, fn ^field, duration ->
      if valid?(duration),
        do: [],
        else: [{field, "must be whole days, weeks, months, or years"}]
    end)
  end

  @doc """
  The day `interval` after `date`. Years and months are added first, then
  days, and a step past a short month's end lands on its last day, as
  Postgres adds an interval to a date.
  """
  def next_on(%Date{} = date, %Duration{} = interval), do: Date.shift(date, interval)

  defp normalize(%Duration{} = duration) do
    months = 12 * duration.year + duration.month
    days = 7 * duration.week + duration.day
    microseconds = elem(duration.microsecond, 0)

    Duration.new!(
      year: div(months, 12),
      month: rem(months, 12),
      day: days,
      hour: duration.hour,
      minute: duration.minute,
      second: duration.second,
      microsecond: {microseconds, if(microseconds == 0, do: 0, else: 6)}
    )
  end
end
