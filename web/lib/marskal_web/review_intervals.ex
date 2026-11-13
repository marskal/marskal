defmodule MarskalWeb.ReviewIntervals do
  @moduledoc """
  Choosing a review interval and saying it in words (ADR 0026).

  The picker is a number and a unit: days, weeks, months, or years, or
  Never. It posts `unit` (one of `units/0`, "never", or "keep") and
  `count` (the number), which `read/2` turns into the value to save. A
  mixed interval, which only an import or another client can make, shows
  as one more option in its words, posted as "keep", so that it stays
  until another is picked.
  """

  use MarskalWeb, :html

  @units ["day", "week", "month", "year"]
  @max_count 999

  @doc "The units a picker offers besides Never."
  def units, do: @units

  @doc """
  The count and unit an interval shows as: `{nil, "never"}` for nil, a
  whole number of weeks as weeks, months and years together as months
  unless they are whole years, and `{nil, "keep"}` for a mixed interval.
  """
  def split(nil), do: {nil, "never"}

  def split(%Duration{year: 0, month: 0, day: days}) when rem(days, 7) == 0,
    do: {div(days, 7), "week"}

  def split(%Duration{year: 0, month: 0, day: days}), do: {days, "day"}
  def split(%Duration{year: years, month: 0, day: 0}), do: {years, "year"}
  def split(%Duration{year: years, month: months, day: 0}), do: {12 * years + months, "month"}
  def split(%Duration{}), do: {nil, "keep"}

  @doc """
  What a picker's post means: `{:ok, interval}` (nil for Never), `:keep`
  for a mixed interval left as it is, `:pending` while the number is
  empty, or `{:error, message}` for a number that is not a whole one in
  range. A post without a number, as when Never is changed to a unit,
  counts one.
  """
  def read("never", _count), do: {:ok, nil}
  def read("keep", _count), do: :keep
  def read(unit, nil) when unit in @units, do: read(unit, "1")

  def read(unit, count) when unit in @units and is_binary(count) do
    case String.trim(count) do
      "" ->
        :pending

      text ->
        case Integer.parse(text) do
          {n, ""} when n in 1..@max_count -> {:ok, interval(n, unit)}
          _ -> {:error, gettext("Use a whole number from 1 to %{max}.", max: @max_count)}
        end
    end
  end

  def read(_unit, _count), do: {:error, gettext("Pick an interval.")}

  defp interval(n, "day"), do: Duration.new!(day: n)
  defp interval(n, "week"), do: Duration.new!(day: 7 * n)
  defp interval(n, "month"), do: Duration.new!(year: div(n, 12), month: rem(n, 12))
  defp interval(n, "year"), do: Duration.new!(year: n)

  defp unit_label("day", n), do: ngettext("day", "days", n)
  defp unit_label("week", n), do: ngettext("week", "weeks", n)
  defp unit_label("month", n), do: ngettext("month", "months", n)
  defp unit_label("year", n), do: ngettext("year", "years", n)

  @doc """
  The interval in words: whole weeks as weeks, a single unit as that unit,
  and a mixed one in its parts. Nil is Never.
  """
  def words(nil), do: gettext("Never")

  def words(%Duration{year: 0, month: 0, day: days}) when days > 0 and rem(days, 7) == 0,
    do: ngettext("Every week", "Every %{count} weeks", div(days, 7))

  def words(%Duration{year: years, month: 0, day: 0}) when years > 0,
    do: ngettext("Every year", "Every %{count} years", years)

  def words(%Duration{year: 0, month: months, day: 0}) when months > 0,
    do: ngettext("Every month", "Every %{count} months", months)

  def words(%Duration{year: 0, month: 0, day: days}) when days > 0,
    do: ngettext("Every day", "Every %{count} days", days)

  def words(%Duration{} = interval) do
    parts =
      [
        interval.year > 0 && ngettext("1 year", "%{count} years", interval.year),
        interval.month > 0 && ngettext("1 month", "%{count} months", interval.month),
        interval.day > 0 && ngettext("1 day", "%{count} days", interval.day)
      ]
      |> Enum.filter(& &1)

    gettext("Every %{parts}", parts: Enum.join(parts, ", "))
  end

  attr :id, :string, required: true
  attr :name, :string, required: true, doc: "the param the unit posts as"
  attr :count_name, :string, required: true, doc: "the param the number posts as"
  attr :label, :string, required: true
  attr :interval, :any, required: true, doc: "the saved interval, or nil for Never"
  attr :unit, :string, default: nil, doc: "the unit as last posted"
  attr :count, :string, default: nil, doc: "the number as last posted"
  attr :error, :string, default: nil

  @doc """
  The interval picker: a number, hidden for Never, and a select of units.
  What was last posted stays shown while it is pending, wrong, or what is
  saved, so 14 days typed is not turned into 2 weeks under the cursor.
  """
  def picker(assigns) do
    {count, unit} = shown(assigns)

    options =
      [{gettext("Never"), "never"}] ++
        Enum.map(@units, &{unit_label(&1, label_count(count)), &1}) ++
        if(unit == "keep", do: [{words(assigns.interval), "keep"}], else: [])

    assigns = assign(assigns, shown_unit: unit, shown_count: count, options: options)

    ~H"""
    <div class="field review-interval" id={@id}>
      <style :type={MarskalWeb.ColocatedCSS}>
        @scope (.review-interval) {
          .row {
            display: flex;
            gap: 0.5rem;
          }
          input {
            width: 5rem;
          }
          .hint.error {
            color: var(--danger);
          }
        }
      </style>
      <label for={"#{@id}-#{if @shown_unit in units(), do: "count", else: "unit"}"}>
        {@label}
      </label>
      <div class="row">
        <input
          :if={@shown_unit in units()}
          id={"#{@id}-count"}
          class="input"
          type="number"
          name={@count_name}
          value={@shown_count}
          min="1"
          max="999"
          step="1"
          inputmode="numeric"
          autocomplete="off"
          aria-describedby={@error && "#{@id}-error"}
          phx-debounce="300"
        />
        <select id={"#{@id}-unit"} class="input" name={@name} aria-label={gettext("Unit")}>
          <option :for={{label, value} <- @options} value={value} selected={value == @shown_unit}>
            {label}
          </option>
        </select>
      </div>
      <p :if={@error} id={"#{@id}-error"} class="hint error" aria-live="polite">{@error}</p>
    </div>
    """
  end

  defp shown(%{unit: unit, count: count, interval: interval, error: error})
       when is_binary(unit) do
    if error || read(unit, count) in [:pending, {:ok, interval}],
      do: {count || "1", unit},
      else: split_text(interval)
  end

  defp shown(%{interval: interval}), do: split_text(interval)

  defp split_text(interval) do
    case split(interval) do
      {nil, unit} -> {"1", unit}
      {n, unit} -> {Integer.to_string(n), unit}
    end
  end

  # Unit names agree with the number; an empty one reads as plural.
  defp label_count(text) do
    case Integer.parse(text || "") do
      {n, _} when n > 0 -> n
      _ -> 2
    end
  end
end
