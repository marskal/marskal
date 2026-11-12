defmodule MarskalWeb.ReviewLive do
  @moduledoc """
  The projects due for review (ADR 0026), by next review day, then in
  sidebar order. Each row says its folder, its deferral, and whether it
  is stalled. Opening one shows the project with a Mark reviewed bar,
  which moves on to the next due project. The Inbox count is a reminder
  to clear it; it blocks nothing.
  """

  use MarskalWeb, :live_view

  alias Marskal.Projects
  alias Marskal.Review

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, gettext("Review")) |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_nav={:review}
      inspector={assigns[:inspector]}
      nav={assigns[:nav]}
      change_version={assigns[:change_version] || 0}
      visibility={assigns[:visibility]}
    >
      <style :type={MarskalWeb.ColocatedCSS}>
        @scope (.review-list) {
          :scope {
            list-style: none;
            margin: 0;
            padding: 0;
          }
          .row {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            padding: 0.6rem 0;
            border-bottom: 1px solid var(--border);
          }
          .main {
            flex: 1 1 auto;
            min-width: 0;
          }
          .title {
            font-weight: 500;
          }
          .facts {
            display: flex;
            flex-wrap: wrap;
            gap: 0.25rem 0.75rem;
            color: var(--muted);
            font-size: 0.875rem;
          }
          .fact {
            display: inline-flex;
            align-items: center;
            gap: 0.25rem;
          }
          .fact .icon {
            width: 1rem;
            height: 1rem;
          }
          .stalled {
            color: var(--danger);
          }
        }
      </style>

      <h1>{gettext("Review")}</h1>
      <p :if={@inbox_count > 0} id="review-inbox" class="lede">
        <.link navigate={~p"/inbox"}>
          {ngettext(
            "1 item in the Inbox. Clear it before you review?",
            "%{count} items in the Inbox. Clear them before you review?",
            @inbox_count
          )}
        </.link>
      </p>

      <.empty_state :if={@rows == []} id="review-empty" title={gettext("Nothing to review")}>
        <:icon><Lucideicons.circle_check_big class="icon" /></:icon>
        {gettext("Every project is reviewed. Each comes back here when its next review is due.")}
      </.empty_state>

      <ul :if={@rows != []} id="review-projects" class="review-list">
        <li :for={row <- @rows} id={"review-#{row.project.id}"} class="row">
          <div class="main">
            <.link navigate={~p"/projects/#{row.project.id}?review=1"} class="title">
              {row.project.title}
            </.link>
            <div class="facts">
              <span :if={row.folder} class="fact">
                <Lucideicons.folder class="icon" /> {row.folder.name}
              </span>
              <span :if={row.deferred?} class="fact">
                <Lucideicons.hourglass class="icon" /> {deferral(row.project, @zone)}
              </span>
              <span :if={row.stalled?} class="fact stalled">
                <Lucideicons.circle_alert class="icon" /> {gettext("Stalled: no next action")}
              </span>
              <span class="fact">{due_text(row.project.next_review_on, @today)}</span>
            </div>
          </div>
          <button
            type="button"
            phx-click="reviewed"
            phx-value-id={row.project.id}
            id={"review-#{row.project.id}-done"}
          >
            {gettext("Mark reviewed")}
          </button>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:marskal_change, _type, _id}, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("reviewed", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    case Projects.mark_reviewed(user, id, Ecto.UUID.generate(version: 7)) do
      {:ok, _project} -> {:noreply, load(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not mark it reviewed."))}
    end
  end

  defp load(socket) do
    user = socket.assigns.current_scope.user
    zone = Marskal.Accounts.timezone(user)

    assign(socket,
      rows: Review.due(user),
      inbox_count: length(Marskal.Tasks.list_inbox(user)),
      zone: zone,
      today: Marskal.Dates.today(zone)
    )
  end

  @doc false
  def due_text(date, today) do
    case Date.diff(today, date) do
      0 -> gettext("Due today")
      _ -> gettext("Due since %{day}", day: Marskal.DateFormat.date(date, :day_month))
    end
  end

  defp deferral(%{deferred_indefinitely: true}, _zone), do: gettext("Deferred")

  defp deferral(%{defer_until: until}, zone) do
    gettext("Deferred until %{day}",
      day: MarskalWeb.DateFields.short(until, :defer_until, zone)
    )
  end
end
