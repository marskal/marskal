defmodule MarskalWeb.DateFields do
  @moduledoc """
  Defer, Planned, and Due in the UI (ADR 0006): the inspector's inputs, what
  they post back, and the short labels on task rows. Everything is on the
  wall clock of the user's stored zone.
  """

  use MarskalWeb, :html

  alias Marskal.Dates

  # Form key prefix for each stored field.
  @keys %{defer_until: "defer", planned_at: "planned", due_at: "due"}

  attr :form, :string, required: true, doc: "the form's param name, such as \"task\""
  attr :id, :string, required: true
  attr :record, :any, required: true
  attr :zone, :string, required: true

  attr :inherited, :map,
    default: nil,
    doc:
      "the dates the record goes by (`Marskal.Tasks.effective_dates/2`), to show what it inherits"

  @doc "The three date fields for a task or project."
  def inputs(assigns) do
    ~H"""
    <div class="field dates" id={@id}>
      <.day_time
        label="Defer until"
        form={@form}
        id={@id}
        field={:defer_until}
        record={@record}
        zone={@zone}
        disabled={@record.deferred_indefinitely}
      />
      <p :if={inherited_defer(@record, @inherited, @zone)} class="hint inherited">
        {inherited_defer(@record, @inherited, @zone)}
      </p>
      <label class="indefinite">
        <input type="hidden" name={"#{@form}[deferred_indefinitely]"} value="false" />
        <input
          type="checkbox"
          id={"#{@id}-indefinite"}
          name={"#{@form}[deferred_indefinitely]"}
          value="true"
          checked={@record.deferred_indefinitely}
        /> Defer indefinitely
      </label>
      <.day_time
        label="Planned"
        form={@form}
        id={@id}
        field={:planned_at}
        record={@record}
        zone={@zone}
      />
      <p :if={inherited(@record, @inherited, :planned_at, @zone)} class="hint inherited">
        {inherited(@record, @inherited, :planned_at, @zone)}
      </p>
      <.day_time label="Due" form={@form} id={@id} field={:due_at} record={@record} zone={@zone} />
      <p :if={inherited(@record, @inherited, :due_at, @zone)} class="hint inherited">
        {inherited(@record, @inherited, :due_at, @zone)}
      </p>
      <p class="hint">A day with no time starts at {default_hint()}.</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :form, :string, required: true
  attr :id, :string, required: true
  attr :field, :atom, required: true
  attr :record, :any, required: true
  attr :zone, :string, required: true
  attr :disabled, :boolean, default: false

  defp day_time(assigns) do
    key = Map.fetch!(@keys, assigns.field)

    {date, time} =
      case Map.fetch!(assigns.record, assigns.field) do
        nil -> {nil, nil}
        datetime -> Dates.to_local(datetime, assigns.zone)
      end

    assigns =
      assign(assigns,
        key: key,
        date: date && Date.to_iso8601(date),
        time: time && Calendar.strftime(time, "%H:%M")
      )

    ~H"""
    <div class="day-time">
      <label for={"#{@id}-#{@key}-date"}>{@label}</label>
      <div class="day-time__inputs">
        <input
          id={"#{@id}-#{@key}-date"}
          class="input"
          type="date"
          name={"#{@form}[#{@key}_date]"}
          value={@date}
          disabled={@disabled}
        />
        <input
          id={"#{@id}-#{@key}-time"}
          class="input"
          type="time"
          name={"#{@form}[#{@key}_time]"}
          value={@time}
          disabled={@disabled || is_nil(@date)}
          aria-label={"#{@label} time"}
        />
      </div>
    </div>
    """
  end

  # What a blank field goes by instead, from the task or project above.
  defp inherited(record, inherited, field, zone) do
    value = inherited && Map.get(inherited, field)

    if value && is_nil(Map.fetch!(record, field)),
      do: "From above: #{short(value, field, zone)}"
  end

  defp inherited_defer(record, inherited, zone) do
    cond do
      is_nil(inherited) or not Dates.deferred?(inherited, DateTime.utc_now()) ->
        nil

      Dates.deferred?(record, DateTime.utc_now()) and
        record.deferred_indefinitely == inherited.deferred_indefinitely and
          record.defer_until == inherited.defer_until ->
        nil

      inherited.deferred_indefinitely ->
        "Deferred indefinitely by the task or project above."

      true ->
        "Deferred until #{short(inherited.defer_until, :defer_until, zone)} by the task or project above."
    end
  end

  defp default_hint do
    [:defer_until, :planned_at, :due_at]
    |> Enum.map_join(", ", fn field ->
      "#{Calendar.strftime(Dates.default_time(field), "%H:%M")} (#{field_word(field)})"
    end)
  end

  defp field_word(:defer_until), do: "defer"
  defp field_word(:planned_at), do: "planned"
  defp field_word(:due_at), do: "due"

  @doc """
  The date attrs a form post means for `record`. A field whose day and
  minute match the stored value keeps the stored value, so an untouched
  field is not patched. A field that was not posted, such as a disabled
  input, is cleared.
  """
  def params_to_attrs(params, record, zone) do
    indefinite = params["deferred_indefinitely"] |> List.wrap() |> List.last() == "true"

    dates =
      for {field, key} <- @keys, not (field == :defer_until and indefinite), into: %{} do
        {Atom.to_string(field), instant(params, key, field, record, zone)}
      end

    Map.put(dates, "deferred_indefinitely", indefinite)
  end

  defp instant(params, key, field, record, zone) do
    with {:ok, date} <- Date.from_iso8601(params["#{key}_date"] || "") do
      time =
        case Time.from_iso8601(pad_seconds(params["#{key}_time"])) do
          {:ok, time} -> time
          {:error, _} -> nil
        end

      picked = Dates.from_local(date, time, field, zone)
      stored = Map.fetch!(record, field)

      if stored && same_minute?(stored, picked), do: stored, else: picked
    else
      _ -> nil
    end
  end

  defp pad_seconds(<<_::binary-size(5)>> = hh_mm), do: hh_mm <> ":00"
  defp pad_seconds(value) when is_binary(value), do: value
  defp pad_seconds(_value), do: ""

  defp same_minute?(a, b) do
    DateTime.truncate(a, :second) |> Map.put(:second, 0) ==
      DateTime.truncate(b, :second) |> Map.put(:second, 0)
  end

  ## Row labels

  @doc """
  A short label for an instant: Today, Tomorrow, Yesterday, a weekday in
  the coming week, else the day and month (and year if not this one). The
  time follows when it is not the field's default.
  """
  def short(%DateTime{} = datetime, field, zone, today \\ nil) do
    {date, time} = Dates.to_local(datetime, zone)
    today = today || Dates.today(zone)

    day =
      case Date.diff(date, today) do
        0 -> "Today"
        1 -> "Tomorrow"
        -1 -> "Yesterday"
        n when n in 2..6 -> Calendar.strftime(date, "%a")
        _ when date.year == today.year -> Calendar.strftime(date, "%-d %b")
        _ -> Calendar.strftime(date, "%-d %b %Y")
      end

    if Time.compare(time, Dates.default_time(field)) == :eq,
      do: day,
      else: "#{day} #{Calendar.strftime(time, "%H:%M")}"
  end
end
