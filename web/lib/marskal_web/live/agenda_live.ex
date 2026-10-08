defmodule MarskalWeb.AgendaLive do
  use MarskalWeb, :live_view
  use MarskalWeb.TaskActions, reload: &load_tasks/1

  import MarskalWeb.TaskList, only: [assign_tasks: 2, reset_tasks: 1]

  alias Marskal.Dates
  alias Marskal.Tasks

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Agenda") |> assign(:view, nil)}
  end

  # The agenda is driven by Planned (ADR 0006), on the user's stored zone
  # (ADR 0014). Today also carries earlier plans that are still to do, so a
  # missed day is not lost. Deferred and unavailable tasks are hidden
  # unless ?unavailable=1, as in the open stream. A new day or toggle is a
  # new view, so kept rows go.
  @impl true
  def handle_params(params, _uri, socket) do
    zone = Marskal.Accounts.timezone(socket.assigns.current_scope.user)
    today = Dates.today(zone)

    date =
      case Date.from_iso8601(params["date"] || "") do
        {:ok, date} -> date
        {:error, _} -> today
      end

    view = {date, params["unavailable"] == "1"}

    socket
    |> then(&if(&1.assigns.view == view, do: &1, else: reset_tasks(&1)))
    |> assign(view: view, date: date, today: today, show_unavailable: elem(view, 1))
    |> load_tasks()
    |> then(&{:noreply, &1})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_nav={:agenda}
      inspector={assigns[:inspector]}
      nav={assigns[:nav]}
      change_version={assigns[:change_version] || 0}
    >
      <h1>{heading(@date, @today)}</h1>
      <p class="lede">
        <.link id="agenda-prev" patch={day_path(Date.add(@date, -1), @today, @show_unavailable)}>
          Previous day
        </.link>
        ·
        <.link
          :if={@date != @today}
          id="agenda-today"
          patch={day_path(@today, @today, @show_unavailable)}
        >
          Today
        </.link>
        <span :if={@date != @today}>·</span>
        <.link id="agenda-next" patch={day_path(Date.add(@date, 1), @today, @show_unavailable)}>
          Next day
        </.link>
        ·
        <.link :if={!@show_unavailable} patch={day_path(@date, @today, true)}>
          Show unavailable
        </.link>
        <.link :if={@show_unavailable} patch={day_path(@date, @today, false)}>
          Hide unavailable
        </.link>
      </p>

      <MarskalWeb.TaskComponents.list
        id="agenda-tasks"
        tasks={@tasks}
        tags={@task_tags.tags}
        unavailable={@task_tags.unavailable}
        deferred={@task_tags.deferred}
        dates={@task_tags.dates}
        resolved={@task_tags.resolved}
        parents={@task_tags.parents}
        zone={Marskal.Accounts.timezone(@current_scope.user)}
        mark_inbox
        empty="Nothing planned."
        actions={[:complete]}
        inspector={@inspector}
      />
    </Layouts.app>
    """
  end

  defp load_tasks(socket) do
    %{date: date, today: today, show_unavailable: show} = socket.assigns
    user = socket.assigns.current_scope.user

    assign_tasks(
      socket,
      Tasks.list_planned(user, date, carry_over: date == today, unavailable: show)
    )
  end

  defp heading(date, today) do
    case Date.diff(date, today) do
      0 -> "Today"
      1 -> "Tomorrow"
      -1 -> "Yesterday"
      _ -> Calendar.strftime(date, "%A %-d %B %Y")
    end
  end

  defp day_path(date, today, show_unavailable) do
    query =
      [date: date != today && Date.to_iso8601(date), unavailable: show_unavailable && 1]
      |> Enum.filter(fn {_key, value} -> value end)

    if query == [], do: ~p"/agenda", else: ~p"/agenda?#{query}"
  end
end
