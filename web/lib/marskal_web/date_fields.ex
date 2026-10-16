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
  attr :target, :any, required: true, doc: "the component that handles `date-commit`"

  attr :previews, :map,
    default: %{},
    doc: "what each field's typed text reads as, by key, from `preview/3`"

  attr :calendar, :map,
    default: nil,
    doc: "the open calendar, from `open_calendar/3`, or nil"

  attr :inherited, :map,
    default: nil,
    doc:
      "the dates the record goes by (`Marskal.Tasks.effective_dates/2`), to show what it inherits"

  @doc """
  The three date fields for a task or project. Each is a text field that
  reads what is typed (ADR 0032), over hidden ISO inputs that hold what is
  saved. Typing posts the text, for `preview/3`; Enter or leaving the field
  sends a `date-commit` event with the key and text, for `commit/4`.
  """
  def inputs(assigns) do
    ~H"""
    <div class="field dates" id={@id}>
      <.day_time
        label={gettext("Defer until")}
        form={@form}
        id={@id}
        field={:defer_until}
        record={@record}
        zone={@zone}
        target={@target}
        preview={@previews["defer"]}
        calendar={@calendar}
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
        /> {gettext("Defer indefinitely")}
      </label>
      <.day_time
        label={gettext("Planned")}
        form={@form}
        id={@id}
        field={:planned_at}
        record={@record}
        zone={@zone}
        target={@target}
        preview={@previews["planned"]}
        calendar={@calendar}
      />
      <p :if={inherited(@record, @inherited, :planned_at, @zone)} class="hint inherited">
        {inherited(@record, @inherited, :planned_at, @zone)}
      </p>
      <.day_time
        label={gettext("Due")}
        form={@form}
        id={@id}
        field={:due_at}
        record={@record}
        zone={@zone}
        target={@target}
        preview={@previews["due"]}
        calendar={@calendar}
      />
      <p :if={inherited(@record, @inherited, :due_at, @zone)} class="hint inherited">
        {inherited(@record, @inherited, :due_at, @zone)}
      </p>
      <p class="hint">
        {gettext("Type a day such as “tom”, “fri”, “1w”, or “24/12 14:00”.")}
        {gettext("A day with no time starts at %{times}.", times: default_hint())}
      </p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :form, :string, required: true
  attr :id, :string, required: true
  attr :field, :atom, required: true
  attr :record, :any, required: true
  attr :zone, :string, required: true
  attr :target, :any, required: true
  attr :preview, :any, default: nil
  attr :calendar, :map, default: nil
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
        time: time && Calendar.strftime(time, "%H:%M"),
        saved: text(Map.fetch!(assigns.record, assigns.field), assigns.field, assigns.zone),
        open: match?(%{key: ^key}, assigns.calendar)
      )

    ~H"""
    <div class="day-time">
      <label for={"#{@id}-#{@key}"}>{@label}</label>
      <div class="day-time__entry">
        <input type="hidden" name={"#{@form}[#{@key}_date]"} value={@date} disabled={@disabled} />
        <input type="hidden" name={"#{@form}[#{@key}_time]"} value={@time} disabled={@disabled} />
        <input
          id={"#{@id}-#{@key}"}
          class="input"
          type="text"
          name={"#{@form}[#{@key}_text]"}
          value={typed(@preview) || @saved}
          data-saved={@saved}
          disabled={@disabled}
          autocomplete="off"
          spellcheck="false"
          phx-debounce="150"
          phx-hook=".DateText"
          phx-target={@target}
          data-key={@key}
          data-commit
          aria-describedby={"#{@id}-#{@key}-reads"}
          aria-invalid={to_string(error?(@preview))}
        />
        <button
          type="button"
          id={"#{@id}-#{@key}-calendar-toggle"}
          class="day-time__pick"
          phx-click={if(@open, do: "calendar-close", else: "calendar-open")}
          phx-value-key={@key}
          phx-target={@target}
          disabled={@disabled}
          aria-expanded={to_string(@open)}
          aria-controls={"#{@id}-#{@key}-calendar"}
          aria-label={gettext("Pick a day for %{field}", field: @label)}
        >
          <Lucideicons.calendar_days class="icon" />
        </button>
      </div>
      <.month
        :if={@open}
        id={"#{@id}-#{@key}-calendar"}
        key={@key}
        label={@label}
        calendar={@calendar}
        selected={@date && Date.from_iso8601!(@date)}
        target={@target}
      />
      <p
        id={"#{@id}-#{@key}-reads"}
        class={["hint", "reads", error?(@preview) && "reads--error"]}
        aria-live="polite"
      >
        {preview_text(@preview)}
      </p>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".DateText" extension="ts">
      import {ViewHook} from "phoenix_live_view"

      // Typed text is saved on Enter or on leaving the field, and Esc puts
      // back what is saved (ADR 0032). data-saved is the saved text, so
      // unchanged text sends nothing. The server answers with the field's
      // new text, or nothing when it cannot read it; then it renders the
      // typed text with the error, for the user to fix.
      export default class extends ViewHook<HTMLInputElement> {
        mounted() {
          this.el.addEventListener("keydown", (event) => {
            if (event.key === "Enter") {
              event.preventDefault()
              this.commit()
            } else if (event.key === "Escape" && this.el.value !== this.el.dataset.saved) {
              event.preventDefault()
              event.stopPropagation()
              this.el.value = this.el.dataset.saved ?? ""
              this.el.dispatchEvent(new Event("input", {bubbles: true}))
            }
          })
          this.el.addEventListener("blur", () => this.commit())
        }

        commit() {
          if (this.el.value === this.el.dataset.saved) return
          const payload = {key: this.el.dataset.key, text: this.el.value}
          this.pushEventTo(this.el, "date-commit", payload, (reply: {text?: string}) => {
            if (reply.text !== undefined) this.el.value = reply.text
          })
        }
      }
    </script>
    """
  end

  attr :id, :string, required: true
  attr :key, :string, required: true
  attr :label, :string, required: true
  attr :calendar, :map, required: true
  attr :selected, :any, required: true
  attr :target, :any, required: true

  # A month to pick a day from, its weeks starting on the user's first day.
  defp month(assigns) do
    %{month: month, week_start: week_start} = assigns.calendar
    first = Date.add(month, -Integer.mod(Date.day_of_week(month) - week_start, 7))
    days = Enum.map(0..41, &Date.add(first, &1))

    assigns =
      assign(assigns,
        weeks: Enum.chunk_every(days, 7),
        weekdays: Enum.take(days, 7)
      )

    ~H"""
    <div
      id={@id}
      class="calendar"
      role="dialog"
      aria-label={@label}
      phx-hook=".Calendar"
      phx-click-away="calendar-close"
      phx-target={@target}
    >
      <div class="calendar__head">
        <button
          type="button"
          id={"#{@id}-previous"}
          phx-click="calendar-month"
          phx-value-step="-1"
          phx-target={@target}
          aria-label={gettext("Previous month")}
        >
          <Lucideicons.chevron_left class="icon" />
        </button>
        <p class="calendar__month" aria-live="polite">
          {Marskal.DateFormat.date(@calendar.month, :month_year)}
        </p>
        <button
          type="button"
          id={"#{@id}-next"}
          phx-click="calendar-month"
          phx-value-step="1"
          phx-target={@target}
          aria-label={gettext("Next month")}
        >
          <Lucideicons.chevron_right class="icon" />
        </button>
      </div>
      <table class="calendar__grid" role="grid">
        <thead>
          <tr>
            <th :for={day <- @weekdays} scope="col" abbr={Marskal.DateFormat.date(day, :weekday_long)}>
              {Marskal.DateFormat.date(day, :weekday)}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr :for={week <- @weeks}>
            <td :for={day <- week}>
              <button
                type="button"
                id={"#{@id}-#{Date.to_iso8601(day)}"}
                class={[
                  "calendar__day",
                  day.month != @calendar.month.month && "calendar__day--outside",
                  day == @calendar.today && "calendar__day--today",
                  day == @selected && "calendar__day--selected"
                ]}
                phx-click="calendar-pick"
                phx-value-key={@key}
                phx-value-date={Date.to_iso8601(day)}
                phx-target={@target}
                tabindex={if(day == (@selected || @calendar.today), do: "0", else: "-1")}
                aria-label={Marskal.DateFormat.date(day, :long_year)}
                aria-current={day == @calendar.today && "date"}
                aria-pressed={to_string(day == @selected)}
                data-date={Date.to_iso8601(day)}
              >
                {day.day}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Calendar" extension="ts">
      import {ViewHook} from "phoenix_live_view"

      // The month grid takes focus when it opens. Arrow keys move a day or
      // a week, Page Up and Down a month, and Esc closes it without also
      // closing the inspector. A move past the month asks the server for
      // the next one and lands on the same day there. Closed by a pick or
      // Esc, it hands focus back to its button; a click elsewhere keeps it
      // there.
      export default class extends ViewHook {
        wanted?: string
        refocus = false

        mounted() {
          this.el.addEventListener("click", (event) => {
            if ((event.target as Element).closest("button[data-date]")) this.refocus = true
          })
          this.focusDay()
          this.el.addEventListener("keydown", (event) => {
            if (event.key === "Escape") {
              event.preventDefault()
              event.stopPropagation()
              this.refocus = true
              this.pushEventTo(this.el, "calendar-close", {})
              return
            }
            const button = (event.target as Element).closest<HTMLButtonElement>("button[data-date]")
            if (!button?.dataset.date) return
            const steps: Record<string, number> = {ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7}
            if (event.key in steps) {
              event.preventDefault()
              this.move(addDays(button.dataset.date, steps[event.key]))
            } else if (event.key === "PageUp" || event.key === "PageDown") {
              event.preventDefault()
              this.move(addMonths(button.dataset.date, event.key === "PageUp" ? -1 : 1))
            }
          })
        }

        updated() {
          this.focusDay()
        }

        destroyed() {
          if (this.refocus) document.getElementById(`${this.el.id}-toggle`)?.focus()
        }

        move(date: string) {
          const target = this.el.querySelector<HTMLButtonElement>(`button[data-date="${date}"]:not(.calendar__day--outside)`)
          if (target) {
            this.focus(target)
          } else {
            this.wanted = date
            const step = date < (this.el.querySelector<HTMLButtonElement>("button[data-date]:not(.calendar__day--outside)")?.dataset.date ?? "") ? -1 : 1
            this.pushEventTo(this.el, "calendar-month", {step: String(step)})
          }
        }

        focusDay() {
          const date = this.wanted
          this.wanted = undefined
          const target =
            (date && this.el.querySelector<HTMLButtonElement>(`button[data-date="${date}"]`)) ||
            this.el.querySelector<HTMLButtonElement>("button[tabindex='0']:not(.calendar__day--outside)") ||
            this.el.querySelector<HTMLButtonElement>("button[data-date]:not(.calendar__day--outside)")
          if (target) this.focus(target)
        }

        focus(target: HTMLButtonElement) {
          for (const button of this.el.querySelectorAll<HTMLButtonElement>("button[data-date]")) button.tabIndex = -1
          target.tabIndex = 0
          target.focus()
        }
      }

      function addDays(iso: string, days: number): string {
        const date = new Date(`${iso}T12:00:00Z`)
        date.setUTCDate(date.getUTCDate() + days)
        return date.toISOString().slice(0, 10)
      }

      function addMonths(iso: string, months: number): string {
        const [year, month, day] = iso.split("-").map(Number)
        const last = new Date(Date.UTC(year, month - 1 + months + 1, 0)).getUTCDate()
        return new Date(Date.UTC(year, month - 1 + months, Math.min(day, last))).toISOString().slice(0, 10)
      }
    </script>
    """
  end

  defp typed({:error, text}), do: text
  defp typed(_preview), do: nil

  defp error?(preview), do: match?({:error, _}, preview)

  defp preview_text(nil), do: nil
  defp preview_text({:error, _text}), do: gettext("Can't read that as a day.")
  defp preview_text(:blank), do: gettext("No date")
  defp preview_text({:ok, text}), do: text

  ## Reading typed text (ADR 0032)

  @doc """
  What `text` typed in the field `key` ("defer", "planned", "due") reads as:
  `nil` when it is what the field already shows, `:blank`, `{:error, text}`,
  or `{:ok, text}` naming the day and time it would save.
  """
  def preview(key, text, record, user) do
    field = field(key)
    zone = Marskal.Accounts.timezone(user)

    if text == text(Map.fetch!(record, field), field, zone) do
      nil
    else
      case read(text, field, user) do
        {:ok, date, time} -> {:ok, long(date, time || Dates.default_time(field), zone)}
        :blank -> :blank
        :error -> {:error, text}
      end
    end
  end

  @doc """
  The attrs that saving `text` in the field `key` means: `{:ok, attrs}`, or
  `:error` when it cannot be read. A day and minute the field already has
  keeps the stored instant, so nothing is patched.
  """
  def commit(key, text, record, user) do
    field = field(key)
    zone = Marskal.Accounts.timezone(user)

    case read(text, field, user) do
      :blank ->
        {:ok, %{Atom.to_string(field) => nil}}

      {:ok, date, time} ->
        picked = Dates.from_local(date, time, field, zone)
        stored = Map.fetch!(record, field)
        at = if stored && same_minute?(stored, picked), do: stored, else: picked
        {:ok, %{Atom.to_string(field) => at}}

      :error ->
        :error
    end
  end

  @doc """
  The calendar for the field `key`, at the month of its stored day, else
  this month.
  """
  def open_calendar(key, record, user) do
    preferences = Marskal.Accounts.preferences(user)
    today = Dates.today(preferences.timezone)

    day =
      case Map.fetch!(record, field(key)) do
        nil -> today
        at -> at |> Dates.to_local(preferences.timezone) |> elem(0)
      end

    %{
      key: key,
      month: Date.beginning_of_month(day),
      week_start: preferences.week_start,
      today: today
    }
  end

  @doc "The calendar a month earlier or later."
  def step_calendar(calendar, step),
    do: %{calendar | month: Date.shift(calendar.month, month: step)}

  @doc """
  The attrs that picking `date` in the calendar for `key` means. The stored
  time of day is kept; a field with none takes its default.
  """
  def pick(key, %Date{} = date, record, user) do
    field = field(key)
    zone = Marskal.Accounts.timezone(user)

    time =
      case Map.fetch!(record, field) do
        nil -> nil
        at -> at |> Dates.to_local(zone) |> elem(1)
      end

    %{Atom.to_string(field) => Dates.from_local(date, time, field, zone)}
  end

  @doc """
  The text a date field shows for a stored instant: the day and the time,
  so a day typed without one shows the time it took.
  """
  def text(nil, _field, _zone), do: ""

  def text(%DateTime{} = datetime, _field, zone) do
    {date, time} = Dates.to_local(datetime, zone)
    Marskal.DateFormat.date_time(NaiveDateTime.new!(date, time))
  end

  @doc "The field a key names."
  def field(key), do: @keys |> Enum.find(fn {_field, k} -> k == key end) |> elem(0)

  defp read(text, field, user) do
    preferences = Marskal.Accounts.preferences(user)
    now = preferences.timezone |> DateTime.now!() |> DateTime.to_naive()

    Marskal.DateInput.parse(text, now,
      week_start: preferences.week_start,
      order: Marskal.DateFormat.numeric_order(locale: preferences.locale),
      day_month: Marskal.DateFormat.day_month_order(locale: preferences.locale),
      language: preferences.locale |> String.split("-") |> hd(),
      evening: Dates.evening_time(field)
    )
  end

  # "Friday, 23 October, 17:00", with the year when it is not this one.
  defp long(date, time, zone) do
    style = if date.year == Dates.today(zone).year, do: :long, else: :long_year

    gettext("%{day}, %{time}",
      day: Marskal.DateFormat.date(date, style),
      time: Marskal.DateFormat.time(time)
    )
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
      "#{Marskal.DateFormat.time(Dates.default_time(field))} (#{field_word(field)})"
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
    case Date.from_iso8601(params["#{key}_date"] || "") do
      {:ok, date} -> picked_instant(date, params, key, field, record, zone)
      {:error, _} -> nil
    end
  end

  defp picked_instant(date, params, key, field, record, zone) do
    time =
      case Time.from_iso8601(pad_seconds(params["#{key}_time"])) do
        {:ok, time} -> time
        {:error, _} -> nil
      end

    picked = Dates.from_local(date, time, field, zone)
    stored = Map.fetch!(record, field)

    if stored && same_minute?(stored, picked), do: stored, else: picked
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
        n when n in 2..6 -> Marskal.DateFormat.date(date, :weekday)
        _ when date.year == today.year -> Marskal.DateFormat.date(date, :day_month)
        _ -> Marskal.DateFormat.date(date, :day_month_year)
      end

    if Time.compare(time, Dates.default_time(field)) == :eq,
      do: day,
      else: "#{day} #{Marskal.DateFormat.time(time)}"
  end
end
