defmodule MarskalWeb.RepeatPanel do
  @moduledoc """
  The inspector's Repeat section for a task (ADR 0007): start a series with
  the task as its first occurrence, edit the rule, and stop or resume it.

  A task that does not repeat edits a draft until Start repeating. A rule
  that is running saves on each change, as the rest of the inspector does,
  and every occurrence shares it. Dates are on the user's zone clock.
  """

  use MarskalWeb, :live_component

  alias Marskal.Accounts
  alias Marskal.Dates
  alias Marskal.Recurrence
  alias Marskal.Recurrence.Series

  @frequencies [:minutes, :hours, :days, :weeks, :months, :years]
  @weekday_names ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)
  @ordinals [{1, "1st"}, {2, "2nd"}, {3, "3rd"}, {4, "4th"}, {5, "5th"}, {-1, "last"}]
  @day_kinds [
    monday: "Monday",
    tuesday: "Tuesday",
    wednesday: "Wednesday",
    thursday: "Thursday",
    friday: "Friday",
    saturday: "Saturday",
    sunday: "Sunday",
    work_day: "work day",
    weekend_day: "weekend day"
  ]

  @impl true
  def update(assigns, socket) do
    new_task? = socket.assigns[:task] == nil or socket.assigns.task.id != assigns.task.id
    socket = assign(socket, assigns)
    series = load_series(socket.assigns.user, socket.assigns.task)
    socket = assign(socket, :series, series)

    cond do
      new_task? -> socket |> assign(editing: false, error: nil) |> reset_rule()
      # Keep what the user picked while it does not save.
      socket.assigns.error -> socket
      series -> assign_rule(socket, series)
      true -> socket
    end
    |> then(&{:ok, &1})
  end

  defp load_series(_user, %{series_id: nil}), do: nil
  defp load_series(user, %{series_id: id}), do: Recurrence.get_series(user, id)

  defp reset_rule(%{assigns: %{series: %Series{} = series}} = socket),
    do: socket |> assign(:ends, nil) |> assign_rule(series)

  defp reset_rule(socket) do
    %{user: user, task: task} = socket.assigns

    rule = %Series{
      mode: :regular,
      anchor: default_anchor(task),
      interval: 1,
      frequency: :weeks,
      week_start: Accounts.preferences(user).week_start
    }

    assign(socket, rule: rule, ends: :never)
  end

  # An end picked but not filled in yet saves as no end. The picker stays
  # on it, so the day or number can follow.
  defp assign_rule(socket, series) do
    ends =
      case {ends_mode(series), socket.assigns[:ends]} do
        {:never, picked} when picked in [:date, :count] -> picked
        {mode, _picked} -> mode
      end

    assign(socket, rule: series, ends: ends)
  end

  # The date the task already has, Due first.
  defp default_anchor(task) do
    cond do
      task.due_at -> :due
      task.planned_at -> :planned
      task.defer_until -> :defer
      true -> :due
    end
  end

  defp ends_mode(%Series{end_count: count}) when is_integer(count), do: :count
  defp ends_mode(%Series{ends_at: %DateTime{}}), do: :date
  defp ends_mode(_series), do: :never

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        zone: Accounts.timezone(assigns.user),
        running?: match?(%Series{stopped_at: nil}, assigns.series)
      )

    ~H"""
    <section class="repeat" id={@id}>
      <style :type={MarskalWeb.ColocatedCSS}>
        @scope (.repeat) {
          :scope {
            display: flex;
            flex-direction: column;
            gap: 0.6rem;
            padding-top: 0.75rem;
            border-top: 1px solid var(--border);
          }

          .heading {
            display: flex;
            align-items: center;
            gap: 0.4rem;
            margin: 0;
            font-size: 0.8rem;
            font-weight: 600;
            color: var(--muted);
          }

          .summary {
            margin: 0;
          }

          .row {
            display: grid;
            grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
            gap: 0.4rem;
          }

          .row.every {
            grid-template-columns: 5rem minmax(0, 1fr);
          }

          .days {
            display: grid;
            grid-template-columns: repeat(7, minmax(0, 1fr));
            gap: 0.25rem;
            margin: 0;
            padding: 0;
            border: 0;
          }

          .day {
            position: relative;
            display: flex;
          }

          .day input {
            position: absolute;
            opacity: 0;
            pointer-events: none;
          }

          .day span {
            flex: 1;
            padding: 0.25rem 0;
            border: 1px solid var(--border);
            border-radius: 4px;
            text-align: center;
            font-size: 0.8rem;
            cursor: pointer;
          }

          .day.last {
            grid-column: span 4;
          }

          .day input:checked + span {
            border-color: var(--accent);
            background: color-mix(in srgb, var(--accent) 18%, var(--bg));
          }

          .day input:focus-visible + span {
            outline: 2px solid var(--accent);
            outline-offset: 1px;
          }

          .legend {
            margin: 0 0 0.2rem;
            padding: 0;
            font-size: 0.8rem;
            color: var(--muted);
          }
        }
      </style>
      <h3 class="heading">
        <Lucideicons.repeat class="icon" aria-hidden="true" /> Repeat
      </h3>
      <p :if={@error} class="errors" role="alert">{@error}</p>
      <p :if={@series} class="summary" id={"#{@id}-summary"}>
        {describe(@series, @zone)}
      </p>

      <%= cond do %>
        <% @task.series_id && @series == nil -> %>
          <p class="hint">Its series was deleted, so it no longer repeats.</p>
        <% @series && @series.stopped_at -> %>
          <p class="hint">Stopped. Earlier occurrences stay as they are.</p>
          <div class="actions">
            <button type="button" id={"#{@id}-resume"} phx-click="resume" phx-target={@myself}>
              Resume
            </button>
          </div>
        <% @running? or @editing -> %>
          <.rule_form id={@id} myself={@myself} rule={@rule} ends={@ends} zone={@zone} />
          <div class="actions">
            <button
              :if={@running?}
              type="button"
              id={"#{@id}-stop"}
              phx-click="stop"
              phx-target={@myself}
              data-confirm="Stop repeating? No more occurrences are made. Those made already stay."
            >
              Stop repeating
            </button>
            <button
              :if={!@running?}
              type="button"
              id={"#{@id}-cancel"}
              phx-click="cancel"
              phx-target={@myself}
            >
              Cancel
            </button>
            <button
              :if={!@running?}
              type="submit"
              form={"#{@id}-form"}
              id={"#{@id}-start"}
              class="primary"
            >
              Start repeating
            </button>
          </div>
        <% true -> %>
          <p class="hint">Does not repeat.</p>
          <div class="actions">
            <button type="button" id={"#{@id}-open"} phx-click="edit" phx-target={@myself}>
              Repeat…
            </button>
          </div>
      <% end %>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :myself, :any, required: true
  attr :rule, Series, required: true
  attr :ends, :atom, required: true
  attr :zone, :string, required: true

  defp rule_form(assigns) do
    ~H"""
    <form
      id={"#{@id}-form"}
      class="form"
      phx-change="change"
      phx-submit="start"
      phx-target={@myself}
    >
      <div class="field">
        <label for={"#{@id}-interval"}>Every</label>
        <div class="row every">
          <input
            id={"#{@id}-interval"}
            class="input"
            type="number"
            min="1"
            name="repeat[interval]"
            value={@rule.interval}
            phx-debounce="300"
          />
          <select id={"#{@id}-frequency"} class="input" name="repeat[frequency]">
            <option
              :for={frequency <- frequencies()}
              value={frequency}
              selected={frequency == @rule.frequency}
            >
              {unit(frequency, @rule.interval)}
            </option>
          </select>
        </div>
      </div>

      <fieldset :if={weekly?(@rule)} class="days weekdays" id={"#{@id}-weekdays"}>
        <legend class="legend">On</legend>
        <input type="hidden" name="repeat[weekdays][]" value="" />
        <label :for={day <- week(@rule.week_start)} class="day">
          <input
            type="checkbox"
            name="repeat[weekdays][]"
            value={day}
            checked={day in @rule.weekdays}
            aria-label={weekday_name(day)}
          />
          <span aria-hidden="true">{String.slice(weekday_name(day), 0, 2)}</span>
        </label>
      </fieldset>
      <p :if={weekly?(@rule) and @rule.weekdays == []} class="hint">
        None picked: the same weekday as the date.
      </p>

      <div :if={monthly?(@rule)} class="field">
        <fieldset class="days" id={"#{@id}-month-days"}>
          <legend class="legend">On these days</legend>
          <input type="hidden" name="repeat[month_days][]" value="" />
          <label :for={day <- Enum.to_list(1..31) ++ [-1]} class={["day", day == -1 && "last"]}>
            <input
              type="checkbox"
              name="repeat[month_days][]"
              value={day}
              checked={day in @rule.month_days}
              aria-label={month_day_name(day)}
            />
            <span aria-hidden="true">{if day == -1, do: "Last", else: day}</span>
          </label>
        </fieldset>
        <label for={"#{@id}-ordinal"}>And on the</label>
        <div class="row">
          <select id={"#{@id}-ordinal"} class="input" name="repeat[month_ordinal]">
            <option value="" selected={is_nil(@rule.month_ordinal)}>—</option>
            <option
              :for={{value, label} <- ordinals()}
              value={value}
              selected={value == @rule.month_ordinal}
            >
              {label}
            </option>
          </select>
          <select
            id={"#{@id}-day-kind"}
            class="input"
            name="repeat[month_day_kind]"
            aria-label="Kind of day"
          >
            <option
              :for={{value, label} <- day_kinds()}
              value={value}
              selected={value == (@rule.month_day_kind || :monday)}
            >
              {label}
            </option>
          </select>
        </div>
        <p :if={@rule.month_days == [] and is_nil(@rule.month_ordinal)} class="hint">
          None picked: the same day of the month as the date.
        </p>
      </div>

      <div class="field">
        <label for={"#{@id}-mode"}>Next one comes</label>
        <select id={"#{@id}-mode"} class="input" name="repeat[mode]">
          <option value="regular" selected={@rule.mode == :regular}>On schedule</option>
          <option value="on_completion" selected={@rule.mode == :on_completion}>
            After finishing this one
          </option>
        </select>
        <p class="hint">
          {if @rule.mode == :regular,
            do: "On time even while earlier ones are open, up to #{Recurrence.open_cap()} open.",
            else: "The interval after this one is done or dropped."}
        </p>
      </div>

      <div class="field">
        <label for={"#{@id}-anchor"}>Moves the date</label>
        <select id={"#{@id}-anchor"} class="input" name="repeat[anchor]">
          <option value="due" selected={@rule.anchor == :due}>Due</option>
          <option value="planned" selected={@rule.anchor == :planned}>Planned</option>
          <option value="defer" selected={@rule.anchor == :defer}>Defer until</option>
        </select>
        <p class="hint">The other dates keep their distance from it.</p>
      </div>

      <div class="field">
        <label for={"#{@id}-ends"}>Ends</label>
        <div class="row">
          <select id={"#{@id}-ends"} class="input" name="repeat[ends]">
            <option value="never" selected={@ends == :never}>Never</option>
            <option value="date" selected={@ends == :date}>On a day</option>
            <option value="count" selected={@ends == :count}>After a number</option>
          </select>
          <input
            :if={@ends == :date}
            id={"#{@id}-ends-on"}
            class="input"
            type="date"
            name="repeat[ends_on]"
            value={ends_on(@rule, @zone)}
            aria-label="Last day"
          />
          <input
            :if={@ends == :count}
            id={"#{@id}-end-count"}
            class="input"
            type="number"
            min="1"
            name="repeat[end_count]"
            value={@rule.end_count}
            aria-label="Number of occurrences"
            phx-debounce="300"
          />
        </div>
        <p :if={@ends == :count} class="hint">Counts every one made, this one included.</p>
      </div>
    </form>
    """
  end

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply, socket |> assign(:editing, true) |> assign(:error, nil)}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, socket |> assign(editing: false, error: nil) |> reset_rule()}
  end

  def handle_event("change", %{"repeat" => params}, socket) do
    attrs = params_to_attrs(params, zone(socket))
    ends = ends_param(params)

    case socket.assigns.series do
      %Series{stopped_at: nil} = series ->
        series
        |> then(&Recurrence.update_series(socket.assigns.user, &1.id, attrs, command()))
        |> saved(socket, attrs, ends)

      _ ->
        {:noreply, draft(socket, attrs, ends)}
    end
  end

  def handle_event("start", %{"repeat" => params}, socket) do
    %{user: user, task: task} = socket.assigns
    attrs = params_to_attrs(params, zone(socket))

    case Recurrence.repeat_task(user, task.id, attrs, command()) do
      {:ok, series} ->
        {:noreply,
         socket
         |> assign(series: series, editing: false, error: nil, ends: ends_param(params))
         |> assign_rule(series)}

      {:error, reason} ->
        {:noreply, socket |> draft(attrs, ends_param(params)) |> assign(:error, message(reason))}
    end
  end

  def handle_event("stop", _params, socket) do
    socket.assigns.user
    |> Recurrence.stop_series(socket.assigns.series.id, command())
    |> saved(socket)
  end

  def handle_event("resume", _params, socket) do
    socket.assigns.user
    |> Recurrence.update_series(socket.assigns.series.id, %{stopped_at: nil}, command())
    |> saved(socket)
  end

  defp saved(result, socket, attrs \\ nil, ends \\ nil)

  defp saved({:ok, series}, socket, _attrs, ends) do
    socket = if ends, do: assign(socket, :ends, ends), else: socket
    {:noreply, socket |> assign(series: series, error: nil) |> assign_rule(series)}
  end

  defp saved({:error, reason}, socket, attrs, ends) do
    socket = if attrs, do: draft(socket, attrs, ends), else: socket
    {:noreply, assign(socket, :error, message(reason))}
  end

  # The form shows what was picked, even when it does not save yet.
  defp draft(socket, attrs, ends) do
    base = socket.assigns.series || %Series{week_start: socket.assigns.rule.week_start}

    rule =
      base
      |> Ecto.Changeset.cast(attrs, Map.keys(attrs) |> Enum.map(&String.to_existing_atom/1))
      |> Ecto.Changeset.apply_changes()

    assign(socket, rule: rule, ends: ends)
  end

  defp command, do: Ecto.UUID.generate()

  defp zone(socket), do: Accounts.timezone(socket.assigns.user)

  defp message(%Ecto.Changeset{errors: [{field, error} | _]}),
    do: "#{field_label(field)} #{translate_error(error)}."

  defp message(:already_repeating), do: "This task already repeats."
  defp message(:not_found), do: "That task is not available."
  defp message(_reason), do: "Could not save."

  defp field_label(:anchor), do: "The date it moves"
  defp field_label(:interval), do: "Every"
  defp field_label(:weekdays), do: "Weekdays"
  defp field_label(:month_days), do: "Days of the month"
  defp field_label(:month_ordinal), do: "The nth day"
  defp field_label(:month_day_kind), do: "Kind of day"
  defp field_label(:end_count), do: "The number of occurrences"
  defp field_label(:ends_at), do: "The last day"
  defp field_label(field), do: Phoenix.Naming.humanize(field)

  @doc """
  The rule attrs a form post means. Day limits a frequency or mode does
  not take are cleared, so changing either never leaves a rule that does
  not fit. The end is the whole of `ends_at` and `end_count`.
  """
  def params_to_attrs(params, zone) do
    params
    |> Map.take(~w(mode anchor interval frequency))
    |> Map.merge(day_attrs(params))
    |> Map.merge(end_attrs(params, zone))
  end

  defp day_attrs(%{"mode" => "regular", "frequency" => "weeks"} = params),
    do: Map.put(no_days(), "weekdays", days(params["weekdays"]))

  defp day_attrs(%{"mode" => "regular", "frequency" => "months"} = params) do
    ordinal = blank_to_nil(params["month_ordinal"])

    %{
      no_days()
      | "month_days" => days(params["month_days"]),
        "month_ordinal" => ordinal,
        "month_day_kind" => if(ordinal, do: params["month_day_kind"])
    }
  end

  defp day_attrs(_params), do: no_days()

  defp no_days,
    do: %{"weekdays" => [], "month_days" => [], "month_ordinal" => nil, "month_day_kind" => nil}

  defp end_attrs(%{"ends" => "date"} = params, zone) do
    ends_at =
      case Date.from_iso8601(params["ends_on"] || "") do
        {:ok, date} -> Dates.from_local(date, ~T[23:59:59], :due_at, zone)
        {:error, _} -> nil
      end

    %{"ends_at" => ends_at, "end_count" => nil}
  end

  defp end_attrs(%{"ends" => "count"} = params, _zone),
    do: %{"ends_at" => nil, "end_count" => blank_to_nil(params["end_count"])}

  defp end_attrs(_params, _zone), do: %{"ends_at" => nil, "end_count" => nil}

  defp ends_param(%{"ends" => "date"}), do: :date
  defp ends_param(%{"ends" => "count"}), do: :count
  defp ends_param(_params), do: :never

  defp days(values), do: values |> List.wrap() |> Enum.reject(&(&1 == ""))

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  ## Text

  @doc """
  The rule in a sentence, such as "Every 2 weeks on Tue and Thu, on
  schedule. Moves the Due date. Ends after 6."
  """
  def describe(%Series{} = series, zone) do
    [
      every(series) <> days_text(series) <> mode_text(series),
      "Moves the #{anchor_name(series.anchor)} date.",
      end_text(series, zone)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp every(%Series{interval: 1, frequency: frequency}), do: "Every #{unit(frequency, 1)}"
  defp every(%Series{interval: n, frequency: frequency}), do: "Every #{n} #{unit(frequency, n)}"

  defp days_text(%Series{weekdays: [_ | _] = days, week_start: week_start}) do
    ordered = Enum.filter(week(week_start), &(&1 in days))
    " on " <> join_words(Enum.map(ordered, &String.slice(weekday_name(&1), 0, 3)))
  end

  defp days_text(%Series{month_days: month_days, month_ordinal: ordinal} = series)
       when month_days != [] or not is_nil(ordinal) do
    numbered =
      Enum.map(Enum.sort_by(month_days, &if(&1 == -1, do: 32, else: &1)), &month_day_name/1)

    nth =
      if ordinal,
        do: ["the #{ordinal_name(ordinal)} #{Keyword.fetch!(@day_kinds, series.month_day_kind)}"],
        else: []

    " on " <> join_words(numbered ++ nth)
  end

  defp days_text(_series), do: ""

  defp mode_text(%Series{mode: :regular}), do: ", on schedule."
  defp mode_text(%Series{mode: :on_completion}), do: ", after finishing the last one."

  defp end_text(%Series{end_count: count}, _zone) when is_integer(count),
    do: "Ends after #{count}."

  defp end_text(%Series{ends_at: %DateTime{} = ends_at}, zone) do
    {date, _} = Dates.to_local(ends_at, zone)
    "Ends #{Calendar.strftime(date, "%-d %b %Y")}."
  end

  defp end_text(_series, _zone), do: nil

  defp join_words([one]), do: one

  defp join_words(words) do
    {rest, [last]} = Enum.split(words, -1)
    IO.iodata_to_binary([Enum.intersperse(rest, ", "), " and ", last])
  end

  defp anchor_name(:due), do: "Due"
  defp anchor_name(:planned), do: "Planned"
  defp anchor_name(:defer), do: "Defer"

  defp unit(frequency, 1), do: frequency |> Atom.to_string() |> String.trim_trailing("s")
  defp unit(frequency, _n), do: Atom.to_string(frequency)

  defp frequencies, do: @frequencies
  defp ordinals, do: @ordinals
  defp day_kinds, do: @day_kinds

  defp ordinal_name(ordinal), do: @ordinals |> List.keyfind(ordinal, 0) |> elem(1)

  defp weekday_name(day), do: Enum.at(@weekday_names, day - 1)

  defp month_day_name(-1), do: "the last day"
  defp month_day_name(day), do: "the #{day}#{suffix(day)}"

  defp suffix(day) when day in [11, 12, 13], do: "th"
  defp suffix(day) when rem(day, 10) == 1, do: "st"
  defp suffix(day) when rem(day, 10) == 2, do: "nd"
  defp suffix(day) when rem(day, 10) == 3, do: "rd"
  defp suffix(_day), do: "th"

  # ISO weekdays in the order the week starts on.
  defp week(week_start), do: Enum.map(0..6, &(rem(week_start - 1 + &1, 7) + 1))

  defp weekly?(rule), do: rule.mode == :regular and rule.frequency == :weeks
  defp monthly?(rule), do: rule.mode == :regular and rule.frequency == :months

  defp ends_on(%Series{ends_at: %DateTime{} = ends_at}, zone) do
    {date, _} = Dates.to_local(ends_at, zone)
    Date.to_iso8601(date)
  end

  defp ends_on(_rule, _zone), do: nil
end
