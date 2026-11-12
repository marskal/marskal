defmodule MarskalWeb.ReviewPanel do
  @moduledoc """
  The inspector's review section for a project (ADR 0026): the interval,
  the next review day, when it was last reviewed, and Mark reviewed.

  Picking an interval saves it, and the server moves the next review day
  to match. Custom saves once its text reads as an interval. The next
  review day is a typed day (ADR 0032), saved on Enter or on leaving the
  field, and only while the project is reviewed.
  """

  use MarskalWeb, :live_component

  alias Marskal.Projects
  alias MarskalWeb.ReviewIntervals

  @impl true
  def update(assigns, socket) do
    new_record? = socket.assigns[:record] == nil or socket.assigns.record.id != assigns.record.id

    socket = assign(socket, assigns)

    {:ok,
     if(new_record? or not pending_custom?(socket),
       do: assign(socket, choice: nil, custom: nil, error: nil, next_preview: nil),
       else: socket
     )}
  end

  # A Custom choice still being typed survives a change broadcast.
  defp pending_custom?(socket), do: socket.assigns[:choice] == "custom"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :zone, Marskal.Accounts.timezone(assigns.user))

    ~H"""
    <section class="review" id={@id}>
      <style :type={MarskalWeb.ColocatedCSS}>
        @scope (.review) {
          :scope {
            display: grid;
            gap: 0.5rem;
            padding-top: 0.75rem;
            border-top: 1px solid var(--border);
          }
          h3 {
            margin: 0;
            font-size: 1rem;
          }
          .last {
            margin: 0;
            color: var(--muted);
            font-size: 0.875rem;
          }
          .hint.error {
            color: var(--danger);
          }
        }
      </style>
      <h3>{gettext("Review")}</h3>
      <form id={"#{@id}-interval"} phx-change="interval" phx-target={@myself}>
        <ReviewIntervals.picker
          id={"#{@id}-picker"}
          name="interval"
          custom_name="interval_custom"
          label={gettext("Interval")}
          interval={@record.review_interval}
          choice={@choice}
          custom={@custom}
          error={@error}
        />
      </form>
      <form
        :if={@record.review_interval}
        id={"#{@id}-next"}
        phx-change="preview-next"
        phx-submit="save-next"
        phx-target={@myself}
      >
        <div class="field">
          <label for={"#{@id}-next-day"}>{gettext("Next review")}</label>
          <input
            id={"#{@id}-next-day"}
            class="input"
            type="text"
            name="next"
            value={day_text(@record.next_review_on)}
            autocomplete="off"
            phx-blur="save-next"
            phx-target={@myself}
          />
          <p :if={@next_preview} class="hint" aria-live="polite">{@next_preview}</p>
        </div>
      </form>
      <p :if={@record.review_interval} class="last" id={"#{@id}-last"}>
        {last_text(@record.last_reviewed_at, @zone)}
      </p>
      <button
        :if={@record.review_interval}
        type="button"
        id={"#{@id}-done"}
        phx-click="reviewed"
        phx-target={@myself}
      >
        {gettext("Mark reviewed")}
      </button>
    </section>
    """
  end

  @impl true
  def handle_event("interval", %{"interval" => choice} = params, socket) do
    custom = params["interval_custom"]

    case ReviewIntervals.read(choice, custom) do
      {:ok, interval} ->
        socket = assign(socket, choice: nil, custom: nil, error: nil)
        # Custom text that names a preset stays on Custom while typed.
        socket =
          if choice == "custom",
            do: assign(socket, choice: "custom", custom: custom),
            else: socket

        {:noreply, save(socket, %{review_interval: interval})}

      :pending ->
        {:noreply, assign(socket, choice: "custom", custom: custom || "", error: nil)}

      {:error, message} ->
        {:noreply, assign(socket, choice: choice, custom: custom, error: message)}
    end
  end

  def handle_event("preview-next", %{"next" => text}, socket) do
    preview =
      case MarskalWeb.DateFields.read_day(text, socket.assigns.user) do
        {:ok, date} -> Marskal.DateFormat.date(date, :long_year)
        :blank -> gettext("A reviewed project needs a next review day.")
        :error -> gettext("Can't read that as a day.")
      end

    {:noreply, assign(socket, :next_preview, preview)}
  end

  def handle_event("save-next", params, socket) do
    text = params["next"] || params["value"] || ""
    record = socket.assigns.record

    case MarskalWeb.DateFields.read_day(text, socket.assigns.user) do
      {:ok, date} when date != record.next_review_on ->
        {:noreply, socket |> assign(:next_preview, nil) |> save(%{next_review_on: date})}

      {:ok, _same} ->
        {:noreply, assign(socket, :next_preview, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("reviewed", _params, socket) do
    %{user: user, record: record} = socket.assigns

    case Projects.mark_reviewed(user, record.id, Ecto.UUID.generate(version: 7)) do
      {:ok, project} -> {:noreply, assign(socket, :record, project)}
      {:error, _} -> {:noreply, flash(socket, gettext("Could not mark it reviewed."))}
    end
  end

  defp save(socket, attrs) do
    %{user: user, record: record} = socket.assigns

    case Projects.update_project(user, record.id, attrs, Ecto.UUID.generate(version: 7)) do
      {:ok, project} -> assign(socket, :record, project)
      {:error, _} -> flash(socket, gettext("Could not save the review."))
    end
  end

  defp flash(socket, message) do
    send(self(), {:put_flash, :error, message})
    socket
  end

  defp day_text(nil), do: ""
  defp day_text(date), do: Marskal.DateFormat.date(date, :day_month_year)

  defp last_text(nil, _zone), do: gettext("Not reviewed yet.")

  defp last_text(at, zone) do
    {date, _time} = Marskal.Dates.to_local(at, zone)
    gettext("Last reviewed %{day}.", day: Marskal.DateFormat.date(date, :day_month_year))
  end
end
