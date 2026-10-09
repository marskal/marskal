defmodule MarskalWeb.RepeatPanel do
  @moduledoc """
  The inspector's repeat line for a task, and the dialog that edits its
  rule (ADR 0007): a kind of repeat, then the rule as a sentence with a
  row per day, the next dates, and the end.

  The line says what the rule does and when it comes next. Its menu edits
  the rule, shows the previous occurrence, pauses or resumes, and stops.
  Stopping deletes the series; its occurrences stay as they are.

  The dialog edits a draft, and OK saves it as one command. For a task
  that does not repeat yet, Next is its first date, which becomes the
  task's anchor date. Dates are on the user's zone clock.
  """

  use MarskalWeb, :live_component

  alias Marskal.Accounts
  alias Marskal.Dates
  alias Marskal.Recurrence
  alias Marskal.Recurrence.Series
  alias Phoenix.LiveView.JS

  # The kinds of repeat, as the dialog's first menu offers them, and the
  # frequency each one is.
  @repeats [
    daily: :days,
    weekly: :weeks,
    monthly: :months,
    yearly: :years,
    hourly: :hours,
    minutely: :minutes,
    after: nil
  ]
  @repeat_labels %{
    daily: "daily",
    weekly: "weekly",
    monthly: "monthly",
    yearly: "yearly",
    hourly: "hourly",
    minutely: "by the minute",
    after: "after completion"
  }
  @units [:minutes, :hours, :days, :weeks, :months, :years]
  @weekday_names ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)
  @month_names ~w(January February March April May June July August September October November December)
  @day_kinds [
    day: "day",
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

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:draft, fn -> nil end)
      |> assign_new(:error, fn -> nil end)

    socket = if new_task?, do: assign(socket, draft: nil, error: nil), else: socket
    %{user: user, task: task} = socket.assigns
    series = task.series_id && Recurrence.get_series(user, task.series_id)

    {:ok,
     assign(socket,
       series: series,
       previous: series && Recurrence.previous_occurrence(user, task),
       upcoming: upcoming(series, zone(socket))
     )}
  end

  defp upcoming(nil, _zone), do: []

  defp upcoming(series, zone) do
    case Recurrence.latest_slot(series) do
      nil -> []
      latest -> [latest | Recurrence.upcoming(series, latest, zone, 2)]
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :zone, zone(assigns))

    ~H"""
    <section class="repeat" id={@id}>
      <style :type={MarskalWeb.ColocatedCSS}>
        @scope (.repeat) {
          :scope {
            position: relative;
            padding-top: 0.75rem;
            border-top: 1px solid var(--border);
          }

          .line {
            display: flex;
            align-items: flex-start;
            gap: 0.45rem;
            width: 100%;
            padding: 0.4rem 0.55rem;
            border: 1px solid var(--border);
            border-radius: 6px;
            background: var(--bg);
            color: var(--text);
            font: inherit;
            text-align: left;
          }

          .line .icon {
            flex: none;
            margin-top: 0.15rem;
            color: var(--accent);
          }

          .line .dates {
            color: var(--muted);
          }

          .line.is-paused .icon {
            color: var(--muted);
          }

          .menu {
            position: absolute;
            z-index: 2;
            left: 0;
            margin: 0.25rem 0 0;
            padding: 0.3rem;
            min-width: 14rem;
            list-style: none;
            border: 1px solid var(--border);
            border-radius: 8px;
            background: var(--bg);
            box-shadow: 0 6px 24px color-mix(in srgb, var(--text) 18%, transparent);
          }

          .menu button {
            display: flex;
            align-items: center;
            gap: 0.5rem;
            width: 100%;
            padding: 0.35rem 0.5rem;
            border: 0;
            border-radius: 5px;
            background: transparent;
            color: var(--text);
            text-align: left;
          }

          .menu button:is(:hover, :focus-visible) {
            background: color-mix(in srgb, var(--accent) 12%, var(--bg));
          }

          .menu li.rule {
            margin: 0.25rem 0;
            border-top: 1px solid var(--border);
          }
        }
      </style>

      <%= cond do %>
        <% @task.series_id && @series == nil -> %>
          <p class="hint">Its series was deleted, so it no longer repeats.</p>
        <% @series -> %>
          <button
            type="button"
            id={"#{@id}-line"}
            class={["line", @series.stopped_at && "is-paused"]}
            aria-haspopup="menu"
            phx-click={JS.toggle(to: "##{@id}-menu")}
          >
            <Lucideicons.repeat class="icon" aria-hidden="true" />
            <span>
              <span :if={@series.stopped_at}>Paused · </span>
              <span id={"#{@id}-summary"}>{summary(@series, @zone)}</span>
              <span :if={@upcoming != [] and !@series.stopped_at} class="dates">
                – {Enum.map_join(@upcoming, ", ", &day_label(&1, @zone))}, …
              </span>
            </span>
          </button>
          <ul
            id={"#{@id}-menu"}
            class="menu"
            role="menu"
            hidden
            phx-click-away={JS.hide(to: "##{@id}-menu")}
          >
            <li>
              <button type="button" id={"#{@id}-edit"} phx-click="edit" phx-target={@myself}>
                <Lucideicons.repeat class="icon" aria-hidden="true" /> Edit rule…
              </button>
            </li>
            <li :if={@previous}>
              <button
                type="button"
                id={"#{@id}-previous"}
                phx-click={JS.hide(to: "##{@id}-menu") |> JS.push("inspect")}
                phx-value-type="task"
                phx-value-id={@previous.id}
              >
                <Lucideicons.history class="icon" aria-hidden="true" /> Show previous copy
              </button>
            </li>
            <li class="rule" role="separator"></li>
            <li :if={!@series.stopped_at}>
              <button type="button" id={"#{@id}-pause"} phx-click="pause" phx-target={@myself}>
                <Lucideicons.pause class="icon" aria-hidden="true" /> Pause
              </button>
            </li>
            <li :if={@series.stopped_at}>
              <button type="button" id={"#{@id}-resume"} phx-click="resume" phx-target={@myself}>
                <Lucideicons.play class="icon" aria-hidden="true" /> Resume
              </button>
            </li>
            <li>
              <button
                type="button"
                id={"#{@id}-stop"}
                phx-click="stop"
                phx-target={@myself}
                data-confirm="Stop repeating? The task stays, and so do earlier occurrences, but it cannot repeat again."
              >
                <Lucideicons.x class="icon" aria-hidden="true" /> Stop
              </button>
            </li>
          </ul>
        <% true -> %>
          <button type="button" id={"#{@id}-open"} class="line" phx-click="edit" phx-target={@myself}>
            <Lucideicons.repeat class="icon" aria-hidden="true" /> Repeat…
          </button>
      <% end %>

      <.rule_dialog
        :if={@draft}
        id={"#{@id}-dialog"}
        myself={@myself}
        draft={@draft}
        error={@error}
        running?={@series != nil}
        week_start={week_start(@series, @user)}
        preview={preview(@draft, @series, @task, @user, @zone)}
        zone={@zone}
      />
    </section>
    """
  end

  attr :id, :string, required: true
  attr :myself, :any, required: true
  attr :draft, :map, required: true
  attr :error, :string, default: nil
  attr :running?, :boolean, required: true
  attr :week_start, :integer, required: true
  attr :preview, :list, required: true
  attr :zone, :string, required: true

  defp rule_dialog(assigns) do
    ~H"""
    <dialog
      id={@id}
      class="repeat-dialog"
      phx-hook=".Dialog"
      phx-mounted={JS.ignore_attributes(["open"])}
      aria-labelledby={"#{@id}-title"}
    >
      <style :type={MarskalWeb.ColocatedCSS}>
        @scope (.repeat-dialog) {
          :scope {
            width: min(46rem, calc(100vw - 2rem));
            padding: 1.1rem 1.2rem;
            border: 1px solid var(--border);
            border-radius: 12px;
            background: var(--bg);
            color: var(--text);
          }

          :scope::backdrop {
            background: color-mix(in srgb, var(--text) 30%, transparent);
          }

          form {
            display: flex;
            flex-direction: column;
            gap: 0.9rem;
          }

          .kind {
            display: flex;
            align-items: center;
            gap: 0.6rem;
            margin: 0;
            font-size: 1rem;
            font-weight: 600;
          }

          .kind .icon {
            color: var(--accent);
          }

          .kind select.input {
            width: auto;
            min-width: 12rem;
            font-weight: 400;
          }

          .rule {
            display: flex;
            flex-direction: column;
            gap: 0;
            padding: 0.2rem 0.9rem;
            border-radius: 10px;
            background: color-mix(in srgb, var(--text) 5%, var(--bg));
          }

          .rule > * {
            padding: 0.65rem 0;
          }

          /* The rule reads as a sentence, so its labels are plain text,
             not the inspector's small field labels. */
          .rule label {
            font: inherit;
            color: inherit;
          }

          .rule > * + * {
            border-top: 1px solid var(--border);
          }

          /* The sentence's lead in the first column, right-aligned, so the
             "and on" rows line up under "weeks on". */
          .rows {
            display: grid;
            grid-template-columns: max-content minmax(0, 1fr);
            align-items: center;
            gap: 0.45rem 0.6rem;
          }

          .lead {
            display: flex;
            align-items: center;
            justify-content: flex-end;
            gap: 0.4rem;
            white-space: nowrap;
          }

          .controls {
            display: flex;
            align-items: center;
            gap: 0.4rem;
          }

          .controls {
            flex-wrap: wrap;
          }

          .controls select.input {
            width: auto;
            flex: none;
          }

          .rule input.input.interval {
            width: 3.6rem;
            text-align: center;
          }

          button.round {
            display: inline-grid;
            place-items: center;
            flex: none;
            width: 1.8rem;
            height: 1.8rem;
            padding: 0;
            border: 0;
            border-radius: 999px;
            background: color-mix(in srgb, var(--text) 10%, var(--bg));
            color: var(--text);
          }

          button.round:disabled {
            opacity: 0.35;
          }

          .next {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: 0.4rem 0.6rem;
          }

          .next input.input {
            width: auto;
          }

          .next .dates {
            color: var(--muted);
          }

          .inline {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: 0.4rem 0.6rem;
          }

          .inline select.input,
          .inline input.input {
            width: auto;
          }

          .footer {
            display: flex;
            justify-content: flex-end;
            gap: 0.5rem;
          }
        }
      </style>
      <form
        id={"#{@id}-form"}
        phx-change="change"
        phx-submit="save"
        phx-target={@myself}
        autocomplete="off"
      >
        <h2 class="kind" id={"#{@id}-title"}>
          <Lucideicons.repeat class="icon" aria-hidden="true" />
          <label for={"#{@id}-repeat"}>Repeat</label>
          <select id={"#{@id}-repeat"} class="input" name="repeat[repeat]">
            <option
              :for={{repeat, _} <- repeats()}
              value={repeat}
              selected={repeat == @draft.repeat}
            >
              {repeat_label(repeat)}
            </option>
          </select>
        </h2>

        <p :if={@error} class="errors" role="alert">{@error}</p>

        <div class="rule">
          <.rule_rows id={@id} myself={@myself} draft={@draft} week_start={@week_start} />

          <div :if={@draft.repeat != :after} class="next" id={"#{@id}-next"}>
            <label for={"#{@id}-next-date"}>Next:</label>
            <input
              :if={!@running?}
              id={"#{@id}-next-date"}
              class="input"
              type="date"
              name="repeat[next]"
              value={@draft.next && Date.to_iso8601(@draft.next)}
            />
            <span :if={@running? and @preview != []}>{day_label(hd(@preview), @zone)}</span>
            <span :if={tl_or_empty(@preview) != []} class="dates">
              {Enum.map_join(tl_or_empty(@preview), ", ", &day_label(&1, @zone))}, …
            </span>
          </div>

          <div :if={@draft.repeat == :after and !@running?} class="next">
            <label for={"#{@id}-next-date"}>First:</label>
            <input
              id={"#{@id}-next-date"}
              class="input"
              type="date"
              name="repeat[next]"
              value={@draft.next && Date.to_iso8601(@draft.next)}
            />
          </div>

          <div>
            <div class="inline">
              <label for={"#{@id}-anchor"}>Moves the</label>
              <select id={"#{@id}-anchor"} class="input" name="repeat[anchor]">
                <option value="due" selected={@draft.anchor == :due}>Due</option>
                <option value="planned" selected={@draft.anchor == :planned}>Planned</option>
                <option value="defer" selected={@draft.anchor == :defer}>Defer until</option>
              </select>
              <span>date</span>
            </div>
            <p class="hint">The other dates keep their distance from it.</p>
          </div>

          <div :if={@draft.repeat != :after} class="inline">
            <label for={"#{@id}-ends"}>Ends</label>
            <select id={"#{@id}-ends"} class="input" name="repeat[ends]">
              <option value="never" selected={@draft.ends == :never}>never</option>
              <option value="date" selected={@draft.ends == :date}>after a date</option>
              <option value="count" selected={@draft.ends == :count}>
                after a number of repetitions
              </option>
            </select>
            <input
              :if={@draft.ends == :date}
              id={"#{@id}-ends-on"}
              class="input"
              type="date"
              name="repeat[ends_on]"
              value={@draft.ends_on && Date.to_iso8601(@draft.ends_on)}
              aria-label="Last day"
            />
            <input
              :if={@draft.ends == :count}
              id={"#{@id}-end-count"}
              class="input interval"
              type="number"
              min="1"
              name="repeat[end_count]"
              value={@draft.end_count}
              aria-label="Number of occurrences"
            />
            <span :if={@draft.ends == :count}>in all, this one included</span>
          </div>
        </div>

        <div class="footer">
          <button type="button" id={"#{@id}-cancel"} phx-click="cancel" phx-target={@myself}>
            Cancel
          </button>
          <button type="submit" id={"#{@id}-ok"} class="primary">OK</button>
        </div>
      </form>
    </dialog>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Dialog" extension="ts">
      import {ViewHook} from "phoenix_live_view"

      // The server renders the dialog while its draft is open, and only
      // the server closes it. Patches keep the `open` attribute that
      // showModal() sets (JS.ignore_attributes), Esc asks the server as
      // Cancel does, and a dialog the browser closed some other way tells
      // the server, so the two never disagree about whether it is open.
      // Esc stops at the dialog, so it does not also close the inspector.
      export default class extends ViewHook<HTMLDialogElement> {
        mounted() {
          this.el.addEventListener("keydown", (event) => {
            if (event.key === "Escape") event.stopPropagation()
          })
          this.el.addEventListener("cancel", (event) => {
            event.preventDefault()
            this.pushEventTo(this.el, "cancel", {})
          })
          this.el.addEventListener("close", () => this.pushEventTo(this.el, "cancel", {}))
          this.el.showModal()
        }

        updated() {
          if (!this.el.open) this.el.showModal()
        }
      }
    </script>
    """
  end

  attr :id, :string, required: true
  attr :myself, :any, required: true
  attr :draft, :map, required: true
  attr :week_start, :integer, required: true

  defp rule_rows(%{draft: %{repeat: :after}} = assigns) do
    ~H"""
    <div class="inline" id={"#{@id}-rows"}>
      <.interval id={@id} draft={@draft} />
      <select id={"#{@id}-unit"} class="input" name="repeat[unit]" aria-label="Unit">
        <option :for={unit <- units()} value={unit} selected={unit == @draft.unit}>
          {unit_word(unit, @draft.interval)}
        </option>
      </select>
      <span>after the previous one is done or dropped.</span>
    </div>
    """
  end

  defp rule_rows(%{draft: %{repeat: :weekly}} = assigns) do
    ~H"""
    <div class="rows" id={"#{@id}-rows"}>
      <%= for {day, index} <- Enum.with_index(@draft.weekdays) do %>
        <span class="lead">
          <%= if index == 0 do %>
            Every <.interval id={@id} draft={@draft} /> {unit_word(:weeks, @draft.interval)} on
          <% else %>
            and on
          <% end %>
        </span>
        <span class="controls">
          <select
            id={"#{@id}-weekday-#{index}"}
            class="input"
            name={"repeat[weekdays][#{index}]"}
            aria-label="Weekday"
          >
            <option :for={number <- week(@week_start)} value={number} selected={number == day}>
              {weekday_name(number)}
            </option>
          </select>
          <.row_buttons id={@id} myself={@myself} index={index} count={length(@draft.weekdays)} />
        </span>
      <% end %>
    </div>
    """
  end

  defp rule_rows(%{draft: %{repeat: repeat}} = assigns) when repeat in [:monthly, :yearly] do
    ~H"""
    <div class="rows" id={"#{@id}-rows"}>
      <%= for {{month, ordinal, kind}, index} <- Enum.with_index(@draft.rows) do %>
        <span class="lead">
          <%= if index == 0 do %>
            Every <.interval id={@id} draft={@draft} />
            {unit_word(frequency(@draft), @draft.interval)} on the
          <% else %>
            and the
          <% end %>
        </span>
        <span class="controls">
          <select
            id={"#{@id}-ordinal-#{index}"}
            class="input"
            name={"repeat[rows][#{index}][ordinal]"}
            aria-label="Which"
          >
            <option :for={value <- ordinals(kind)} value={value} selected={value == ordinal}>
              {ordinal_name(value)}
            </option>
          </select>
          <select
            id={"#{@id}-kind-#{index}"}
            class="input"
            name={"repeat[rows][#{index}][kind]"}
            aria-label="Kind of day"
          >
            <option :for={{value, label} <- day_kinds()} value={value} selected={value == kind}>
              {label}
            </option>
          </select>
          <span :if={month}>in</span>
          <select
            :if={month}
            id={"#{@id}-month-#{index}"}
            class="input"
            name={"repeat[rows][#{index}][month]"}
            aria-label="Month"
          >
            <option :for={number <- 1..12} value={number} selected={number == month}>
              {month_name(number)}
            </option>
          </select>
          <.row_buttons id={@id} myself={@myself} index={index} count={length(@draft.rows)} />
        </span>
      <% end %>
    </div>
    """
  end

  defp rule_rows(assigns) do
    ~H"""
    <div class="inline" id={"#{@id}-rows"}>
      Every <.interval id={@id} draft={@draft} /> {unit_word(frequency(@draft), @draft.interval)}
    </div>
    """
  end

  attr :id, :string, required: true
  attr :draft, :map, required: true

  defp interval(assigns) do
    ~H"""
    <input
      id={"#{@id}-interval"}
      class="input interval"
      type="number"
      min="1"
      name="repeat[interval]"
      value={@draft.interval}
      aria-label="How many"
      phx-debounce="300"
    />
    """
  end

  attr :id, :string, required: true
  attr :myself, :any, required: true
  attr :index, :integer, required: true
  attr :count, :integer, required: true

  defp row_buttons(assigns) do
    ~H"""
    <button
      type="button"
      class="round"
      id={"#{@id}-add-#{@index}"}
      phx-click="add-row"
      phx-value-index={@index}
      phx-target={@myself}
      aria-label="Add a day"
    >
      <Lucideicons.plus class="icon" aria-hidden="true" />
    </button>
    <button
      type="button"
      class="round"
      id={"#{@id}-remove-#{@index}"}
      phx-click="remove-row"
      phx-value-index={@index}
      phx-target={@myself}
      disabled={@count == 1}
      aria-label="Remove this day"
    >
      <Lucideicons.minus class="icon" aria-hidden="true" />
    </button>
    """
  end

  ## Events

  @impl true
  def handle_event("edit", _params, socket) do
    %{series: series, task: task} = socket.assigns
    draft = if series, do: draft_from(series, task, zone(socket)), else: new_draft(task, socket)
    {:noreply, assign(socket, draft: draft, error: nil)}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, draft: nil, error: nil)}
  end

  def handle_event("change", %{"repeat" => params}, socket) do
    {:noreply,
     assign(socket, :draft, apply_params(socket.assigns.draft, params, base_date(socket)))}
  end

  def handle_event("add-row", %{"index" => index}, socket) do
    {:noreply, update(socket, :draft, &add_row(&1, String.to_integer(index)))}
  end

  def handle_event("remove-row", %{"index" => index}, socket) do
    {:noreply, update(socket, :draft, &remove_row(&1, String.to_integer(index)))}
  end

  def handle_event("save", params, socket) do
    %{user: user, task: task, series: series} = socket.assigns
    draft = apply_params(socket.assigns.draft, params["repeat"] || %{}, base_date(socket))
    attrs = draft_to_attrs(draft, zone(socket))

    result =
      if series do
        Recurrence.update_series(user, series.id, attrs, command())
      else
        Recurrence.repeat_task(user, task.id, attrs, command(),
          starts_at: starts_at(draft, task, zone(socket))
        )
      end

    case result do
      {:ok, _series} ->
        {:noreply, assign(socket, draft: nil, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, draft: draft, error: message(reason))}
    end
  end

  def handle_event("pause", _params, socket) do
    %{user: user, series: series} = socket.assigns
    act(socket, Recurrence.stop_series(user, series.id, command()))
  end

  def handle_event("resume", _params, socket) do
    %{user: user, series: series} = socket.assigns
    act(socket, Recurrence.update_series(user, series.id, %{stopped_at: nil}, command()))
  end

  def handle_event("stop", _params, socket) do
    %{user: user, series: series} = socket.assigns
    act(socket, Recurrence.delete_series(user, series.id, command()))
  end

  # The change broadcast reloads the panel with the saved series.
  defp act(socket, {:ok, _series}), do: {:noreply, assign(socket, :error, nil)}
  defp act(socket, {:error, reason}), do: {:noreply, assign(socket, :error, message(reason))}

  defp command, do: Ecto.UUID.generate()

  defp zone(%{assigns: assigns}), do: zone(assigns)
  defp zone(%{user: user}), do: Accounts.timezone(user)

  defp week_start(%Series{week_start: week_start}, _user), do: week_start
  defp week_start(nil, user), do: Accounts.preferences(user).week_start

  defp message(%Ecto.Changeset{errors: [{field, error} | _]}),
    do: "#{field_label(field)} #{translate_error(error)}."

  defp message(:already_repeating), do: "This task already repeats."
  defp message(:not_found), do: "That task is not available."
  defp message(_reason), do: "Could not save."

  defp field_label(:anchor), do: "The date it moves"
  defp field_label(:interval), do: "Every"
  defp field_label(:weekdays), do: "Weekdays"
  defp field_label(:on_days), do: "The days"
  defp field_label(:end_count), do: "The number of times"
  defp field_label(:ends_at), do: "The last day"
  defp field_label(field), do: Phoenix.Naming.humanize(field)

  ## The draft

  @doc """
  A draft for a new rule on `task`: weekly, on the weekday of its date.
  Next is the task's anchor date, Due first, or today.
  """
  def new_draft(task, %{assigns: %{user: user}}) do
    zone = Accounts.timezone(user)
    anchor = default_anchor(task)
    field = Series.anchor_field(%Series{anchor: anchor})
    next = local_date(Map.fetch!(task, field), zone) || Dates.today(zone)

    %{repeat: :weekly, interval: 1, unit: :weeks, anchor: anchor, ends: :never}
    |> Map.merge(%{ends_on: nil, end_count: nil, next: next})
    |> reset_days(next)
  end

  @doc "A draft of `series`, as the dialog shows it."
  def draft_from(%Series{} = series, task, zone) do
    date = local_date(Map.fetch!(task, Series.anchor_field(series)), zone) || Dates.today(zone)
    repeat = repeat_of(series)

    draft = %{
      repeat: repeat,
      interval: series.interval,
      unit: series.frequency,
      anchor: series.anchor,
      next: date,
      ends: ends_mode(series),
      ends_on: series.ends_at && local_date(series.ends_at, zone),
      end_count: series.end_count,
      weekdays: series.weekdays,
      rows: Series.day_rules(series)
    }

    # A rule with no days lands on its date's own, which the dialog shows
    # as that day's row.
    if draft.weekdays == [] and draft.rows == [], do: reset_days(draft, date), else: draft
  end

  defp repeat_of(%Series{mode: :on_completion}), do: :after

  defp repeat_of(%Series{frequency: frequency}),
    do: Enum.find_value(@repeats, fn {repeat, f} -> if f == frequency, do: repeat end)

  defp ends_mode(%Series{end_count: count}) when is_integer(count), do: :count
  defp ends_mode(%Series{ends_at: %DateTime{}}), do: :date
  defp ends_mode(_series), do: :never

  # The date it moves, Due first.
  defp default_anchor(task) do
    cond do
      task.due_at -> :due
      task.planned_at -> :planned
      task.defer_until -> :defer
      true -> :due
    end
  end

  defp local_date(nil, _zone), do: nil

  defp local_date(%DateTime{} = at, zone) do
    {date, _} = Dates.to_local(at, zone)
    date
  end

  # The days a new weekly, monthly, or yearly rule starts with: those of
  # `date`.
  defp reset_days(draft, date) do
    Map.merge(draft, %{
      weekdays: [Date.day_of_week(date, :monday)],
      rows:
        case draft.repeat do
          :yearly -> [{date.month, date.day, :day}]
          _ -> [{nil, date.day, :day}]
        end
    })
  end

  defp base_date(socket) do
    draft = socket.assigns.draft
    (draft && draft.next) || Dates.today(zone(socket))
  end

  @doc """
  The draft after a form post. A new kind of repeat starts over with the
  days of `date`. A row's ordinal that its kind of day cannot take becomes
  the first.
  """
  def apply_params(draft, params, date) do
    repeat = pick(Keyword.keys(@repeats), params["repeat"], draft.repeat)
    next = parse_date(params["next"]) || draft.next

    updated = %{
      draft
      | repeat: repeat,
        next: next,
        interval: params["interval"] || draft.interval,
        unit: pick(@units, params["unit"], draft.unit),
        anchor: pick([:due, :planned, :defer], params["anchor"], draft.anchor),
        ends: pick([:never, :date, :count], params["ends"], draft.ends),
        ends_on: parse_date(params["ends_on"]) || draft.ends_on,
        end_count: params["end_count"] || draft.end_count
    }

    if repeat == draft.repeat do
      %{
        updated
        | weekdays: parse_weekdays(params["weekdays"], draft.weekdays),
          rows: parse_rows(params["rows"], draft.rows, repeat)
      }
    else
      reset_days(updated, next || date)
    end
  end

  defp pick(values, value, default) when is_binary(value),
    do: Enum.find(values, default, &(Atom.to_string(&1) == value))

  defp pick(_values, _value, default), do: default

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp parse_date(_value), do: nil

  defp parse_weekdays(params, current) when is_map(params) do
    current = List.to_tuple(current)

    params
    |> indexed()
    |> Enum.map(fn {index, value} ->
      case Integer.parse(value) do
        {day, ""} when day in 1..7 -> day
        _ -> at(current, index, 1)
      end
    end)
  end

  defp parse_weekdays(_params, current), do: current

  defp parse_rows(params, current, repeat) when is_map(params) do
    current = List.to_tuple(current)

    params
    |> indexed()
    |> Enum.map(fn {index, row} ->
      {month, ordinal, kind} = at(current, index, {nil, 1, :day})
      kind = pick(Keyword.keys(@day_kinds), row["kind"], kind)
      ordinal = parse_integer(row["ordinal"], ordinal)
      month = if repeat == :yearly, do: parse_integer(row["month"], month || 1), else: nil
      ordinal = if ordinal in ordinals(kind), do: ordinal, else: 1
      {month, ordinal, kind}
    end)
  end

  defp parse_rows(_params, current, _repeat), do: current

  defp at(tuple, index, _default) when index < tuple_size(tuple), do: elem(tuple, index)
  defp at(_tuple, _index, default), do: default

  defp indexed(params) do
    params
    |> Enum.flat_map(fn {key, value} ->
      case Integer.parse(key) do
        {index, ""} -> [{index, value}]
        _ -> []
      end
    end)
    |> Enum.sort()
  end

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> default
    end
  end

  defp parse_integer(_value, default), do: default

  # A new row repeats the one it follows: the next weekday, or the same
  # day, which the user then changes.
  defp add_row(%{repeat: :weekly} = draft, index) do
    day = Enum.at(draft.weekdays, index)
    %{draft | weekdays: List.insert_at(draft.weekdays, index + 1, rem(day, 7) + 1)}
  end

  defp add_row(draft, index) do
    %{draft | rows: List.insert_at(draft.rows, index + 1, Enum.at(draft.rows, index))}
  end

  defp remove_row(%{repeat: :weekly, weekdays: [_, _ | _]} = draft, index),
    do: %{draft | weekdays: List.delete_at(draft.weekdays, index)}

  defp remove_row(%{rows: [_, _ | _]} = draft, index),
    do: %{draft | rows: List.delete_at(draft.rows, index)}

  defp remove_row(draft, _index), do: draft

  @doc """
  The series attrs a draft means. The days a kind of repeat does not take
  are cleared, so a rule never mixes them.
  """
  def draft_to_attrs(draft, zone) do
    frequency = frequency(draft)

    %{
      "mode" => if(draft.repeat == :after, do: "on_completion", else: "regular"),
      "anchor" => Atom.to_string(draft.anchor),
      "interval" => draft.interval,
      "frequency" => Atom.to_string(frequency),
      "weekdays" =>
        if(frequency == :weeks and draft.repeat == :weekly, do: draft.weekdays, else: []),
      "on_days" =>
        if(draft.repeat in [:monthly, :yearly],
          do: Enum.map(draft.rows, &Series.format_day/1),
          else: []
        )
    }
    |> Map.merge(end_attrs(draft, zone))
  end

  defp end_attrs(%{repeat: :after}, _zone), do: %{"ends_at" => nil, "end_count" => nil}

  defp end_attrs(%{ends: :date, ends_on: %Date{} = day}, zone),
    do: %{"ends_at" => Dates.from_local(day, ~T[23:59:59], :due_at, zone), "end_count" => nil}

  defp end_attrs(%{ends: :count, end_count: count}, _zone),
    do: %{"ends_at" => nil, "end_count" => count}

  defp end_attrs(_draft, _zone), do: %{"ends_at" => nil, "end_count" => nil}

  defp frequency(%{repeat: :after, unit: unit}), do: unit
  defp frequency(%{repeat: repeat}), do: Keyword.fetch!(@repeats, repeat)

  # Next on the task's own time of day for that date, or the date's default.
  defp starts_at(%{next: nil}, _task, _zone), do: nil

  defp starts_at(draft, task, zone) do
    field = Series.anchor_field(%Series{anchor: draft.anchor})

    time =
      case Map.fetch!(task, field) do
        nil -> nil
        at -> at |> Dates.to_local(zone) |> elem(1)
      end

    Dates.from_local(draft.next, time, field, zone)
  end

  # The first date and the three after it, as the rule in the draft gives
  # them. A running series counts from its latest occurrence.
  defp preview(draft, series, task, user, zone) do
    attrs = draft_to_attrs(draft, zone)
    changeset = Series.create_changeset(%Series{}, user, Map.put(attrs, "kind", "task"))
    first = if series, do: Recurrence.latest_slot(series), else: starts_at(draft, task, zone)

    if changeset.valid? and first do
      rule = %{Ecto.Changeset.apply_changes(changeset) | week_start: week_start(series, user)}
      [first | Recurrence.upcoming(rule, first, zone, 3)]
    else
      []
    end
  end

  defp tl_or_empty([_ | rest]), do: rest
  defp tl_or_empty([]), do: []

  ## Text

  @doc """
  The rule in a phrase, as the inspector line shows it: "Repeats weekly
  on Wed and Fri", "Repeats every 2 months on the 14th and the last day",
  "Repeats 1 week after completion".
  """
  def summary(%Series{mode: :on_completion} = series, _zone),
    do:
      "Repeats #{series.interval} #{unit_word(series.frequency, series.interval)} after completion"

  def summary(%Series{} = series, zone) do
    IO.iodata_to_binary(["Repeats ", every(series), days_text(series), end_text(series, zone)])
  end

  defp every(%Series{interval: 1, frequency: frequency}) do
    case frequency do
      :minutes -> "every minute"
      :hours -> "hourly"
      :days -> "daily"
      :weeks -> "weekly"
      :months -> "monthly"
      :years -> "yearly"
    end
  end

  defp every(%Series{interval: n, frequency: frequency}),
    do: "every #{n} #{unit_word(frequency, n)}"

  defp days_text(%Series{weekdays: [_ | _] = days, week_start: week_start}) do
    ordered = Enum.filter(week(week_start), &(&1 in days))
    [" on ", join_words(Enum.map(ordered, &String.slice(weekday_name(&1), 0, 3)))]
  end

  defp days_text(%Series{on_days: [_ | _]} = series) do
    [" on ", series |> Series.day_rules() |> Enum.map(&row_text/1) |> join_words()]
  end

  defp days_text(_series), do: []

  defp row_text({nil, day, :day}) when day < 0, do: "the #{ordinal_name(day)} day"
  defp row_text({nil, day, :day}), do: "the #{ordinal_name(day)}"
  defp row_text({nil, ordinal, kind}), do: "the #{ordinal_name(ordinal)} #{kind_name(kind)}"

  defp row_text({month, day, :day}) when day < 0,
    do: "the #{ordinal_name(day)} day of #{short_month(month)}"

  defp row_text({month, day, :day}), do: "#{day} #{short_month(month)}"

  defp row_text({month, ordinal, kind}),
    do: "the #{ordinal_name(ordinal)} #{kind_name(kind)} in #{short_month(month)}"

  defp end_text(%Series{end_count: count}, _zone) when is_integer(count),
    do: ", #{count} repetitions"

  defp end_text(%Series{ends_at: %DateTime{} = ends_at}, zone),
    do: ", until #{Calendar.strftime(local_date(ends_at, zone), "%-d %b %Y")}"

  defp end_text(_series, _zone), do: []

  defp join_words([one]), do: one

  defp join_words(words) do
    {rest, [last]} = Enum.split(words, -1)
    [Enum.intersperse(rest, ", "), " and ", last]
  end

  defp day_label(at, zone), do: MarskalWeb.DateFields.short(at, :due_at, zone) |> drop_time()

  # The row shows days; the time is the task's own.
  defp drop_time(label), do: String.replace(label, ~r/ \d\d:\d\d$/, "")

  defp unit_word(unit, interval) when interval in [1, "1"],
    do: unit |> Atom.to_string() |> String.trim_trailing("s")

  defp unit_word(unit, _interval), do: Atom.to_string(unit)

  defp repeats, do: @repeats
  defp repeat_label(repeat), do: Map.fetch!(@repeat_labels, repeat)
  defp units, do: @units
  defp day_kinds, do: @day_kinds
  defp kind_name(kind), do: Keyword.fetch!(@day_kinds, kind)

  defp ordinals(:day), do: Enum.to_list(1..31) ++ Enum.to_list(-5..-1//1)
  defp ordinals(_kind), do: [1, 2, 3, 4, 5, -5, -4, -3, -2, -1]

  defp ordinal_name(-1), do: "last"
  defp ordinal_name(n) when n < 0, do: "#{ordinal_name(-n)} to last"
  defp ordinal_name(n), do: "#{n}#{suffix(n)}"

  defp suffix(n) when n in [11, 12, 13], do: "th"
  defp suffix(n) when rem(n, 10) == 1, do: "st"
  defp suffix(n) when rem(n, 10) == 2, do: "nd"
  defp suffix(n) when rem(n, 10) == 3, do: "rd"
  defp suffix(_n), do: "th"

  defp weekday_name(day), do: Enum.at(@weekday_names, day - 1)
  defp month_name(month), do: Enum.at(@month_names, month - 1)
  defp short_month(month), do: String.slice(month_name(month), 0, 3)

  # ISO weekdays in the order the week starts on.
  defp week(week_start), do: Enum.map(0..6, &(rem(week_start - 1 + &1, 7) + 1))
end
