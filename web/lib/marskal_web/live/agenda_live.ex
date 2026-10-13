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

  # The agenda lists what is due and what is planned (ADR 0006), on the
  # user's stored zone (ADR 0014). Today also carries earlier plans and
  # dues that are still to do, so a missed day is not lost. Deferred and
  # unavailable tasks are hidden unless ?unavailable=1, as in the open
  # stream; a later day counts what is deferred until within it as
  # available. A new day or toggle is a new view, so kept rows go.
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

      <.empty_state
        :if={@tasks == []}
        id="agenda-empty"
        title={"Nothing planned or due #{day_name(@date, @today)}"}
      >
        <:icon><Lucideicons.calendar_check class="icon" /></:icon>
        Set a task or project as planned or due {if Date.diff(@date, @today) in -1..1,
          do: day_name(@date, @today),
          else: "that day"} to have it show up here.
      </.empty_state>

      <div :if={@tasks != []} class="agenda-columns">
        <section class="agenda-section" aria-labelledby="agenda-due-heading">
          <h2 id="agenda-due-heading">{if @date == @today, do: "Due and overdue", else: "Due"}</h2>
          <MarskalWeb.TaskComponents.list
            id="agenda-due"
            tasks={@due_tasks}
            tags={@task_tags.tags}
            unavailable={@task_tags.unavailable}
            deferred={@task_tags.deferred}
            dates={@task_tags.dates}
            resolved={@task_tags.resolved}
            parents={@task_tags.parents}
            repeating={@task_tags.repeating}
            flagged={@task_tags.flagged}
            zone={Marskal.Accounts.timezone(@current_scope.user)}
            mark_inbox
            empty="Nothing due."
            actions={[:complete]}
            inspector={@inspector}
          />
        </section>
        <section class="agenda-section" aria-labelledby="agenda-planned-heading">
          <h2 id="agenda-planned-heading">Planned</h2>
          <MarskalWeb.TaskComponents.list
            id="agenda-tasks"
            tasks={@planned_tasks}
            tags={@task_tags.tags}
            unavailable={@task_tags.unavailable}
            deferred={@task_tags.deferred}
            dates={@task_tags.dates}
            resolved={@task_tags.resolved}
            parents={@task_tags.parents}
            repeating={@task_tags.repeating}
            flagged={@task_tags.flagged}
            zone={Marskal.Accounts.timezone(@current_scope.user)}
            mark_inbox
            empty="Nothing planned."
            actions={[:complete]}
            inspector={@inspector}
          />
        </section>
      </div>
    </Layouts.app>
    """
  end

  # A task both due and planned shows once, under Due. Rows that linger
  # after Done stay in the column they were in.
  defp load_tasks(socket) do
    %{date: date, today: today, show_unavailable: show} = socket.assigns
    user = socket.assigns.current_scope.user
    due = Tasks.list_due(user, date, overdue: date == today, unavailable: show)
    due_ids = MapSet.new(due, & &1.id)

    planned =
      user
      |> Tasks.list_planned(date, carry_over: date == today, unavailable: show)
      |> Enum.reject(&MapSet.member?(due_ids, &1.id))

    was_due = if socket.assigns[:tasks] == [], do: MapSet.new(), else: socket.assigns[:due_ids]
    due_ids = MapSet.union(due_ids, was_due || MapSet.new())
    socket = assign_tasks(socket, due ++ planned)
    {due, planned} = Enum.split_with(socket.assigns.tasks, &MapSet.member?(due_ids, &1.id))

    assign(socket, due_ids: due_ids, due_tasks: due, planned_tasks: planned)
  end

  defp heading(date, today) do
    case Date.diff(date, today) do
      0 -> "Today"
      1 -> "Tomorrow"
      -1 -> "Yesterday"
      _ -> Marskal.DateFormat.date(date, :long_year)
    end
  end

  defp day_name(date, today) do
    case Date.diff(date, today) do
      0 -> "today"
      1 -> "tomorrow"
      -1 -> "yesterday"
      _ when date.year == today.year -> Marskal.DateFormat.date(date, :long)
      _ -> Marskal.DateFormat.date(date, :long_year)
    end
  end

  defp day_path(date, today, show_unavailable) do
    query =
      [date: date != today && Date.to_iso8601(date), unavailable: show_unavailable && 1]
      |> Enum.filter(fn {_key, value} -> value end)

    if query == [], do: ~p"/agenda", else: ~p"/agenda?#{query}"
  end
end
