defmodule MarskalWeb.DatesLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  alias Marskal.Dates
  alias Marskal.Projects
  alias Marskal.Tasks

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "the agenda shows today's plans and earlier open ones", %{conn: conn, user: user} do
    today = Dates.today(Marskal.Accounts.timezone(user))
    at = fn date -> Dates.from_local(date, nil, :planned_at, Marskal.Accounts.timezone(user)) end

    {:ok, _} = Tasks.create_task(user, %{title: "Today", planned_at: at.(today)}, command())

    {:ok, _} =
      Tasks.create_task(user, %{title: "Missed", planned_at: at.(Date.add(today, -2))}, command())

    {:ok, _} =
      Tasks.create_task(
        user,
        %{title: "Tomorrow", planned_at: at.(Date.add(today, 1))},
        command()
      )

    {:ok, view, _html} = live(conn, ~p"/agenda")
    assert has_element?(view, "#agenda-tasks", "Today")
    assert has_element?(view, "#agenda-tasks", "Missed")
    refute has_element?(view, "#agenda-tasks", "Tomorrow")

    view |> element("#agenda-next") |> render_click()
    assert has_element?(view, "#agenda-tasks", "Tomorrow")
    refute has_element?(view, "#agenda-tasks", "Missed")
  end

  test "the agenda lists what is due, and today what is overdue", %{conn: conn, user: user} do
    zone = Marskal.Accounts.timezone(user)
    today = Dates.today(zone)
    due = fn date -> Dates.from_local(date, nil, :due_at, zone) end
    planned = fn date -> Dates.from_local(date, nil, :planned_at, zone) end

    {:ok, _} = Tasks.create_task(user, %{title: "Due today", due_at: due.(today)}, command())

    {:ok, _} =
      Tasks.create_task(user, %{title: "Overdue", due_at: due.(Date.add(today, -3))}, command())

    {:ok, _} =
      Tasks.create_task(
        user,
        %{title: "Both", due_at: due.(today), planned_at: planned.(today)},
        command()
      )

    {:ok, _} =
      Tasks.create_task(user, %{title: "Due later", due_at: due.(Date.add(today, 2))}, command())

    {:ok, view, _html} = live(conn, ~p"/agenda")
    assert has_element?(view, "#agenda-due-heading", "Due and overdue")
    assert has_element?(view, "#agenda-due", "Due today")
    assert has_element?(view, "#agenda-due", "Overdue")
    assert has_element?(view, "#agenda-due", "Both")
    refute has_element?(view, "#agenda-tasks", "Both")
    refute has_element?(view, "#agenda-due", "Due later")

    {:ok, view, _html} = live(conn, ~p"/agenda?#{[date: Date.to_iso8601(Date.add(today, 2))]}")
    assert has_element?(view, "#agenda-due-heading", "Due")
    assert has_element?(view, "#agenda-due", "Due later")
    refute has_element?(view, "#agenda-due", "Overdue")
    assert has_element?(view, "#agenda-planned-heading ~ p.empty", "Nothing planned.")
  end

  test "the agenda keeps a task done from Due under Due", %{conn: conn, user: user} do
    zone = Marskal.Accounts.timezone(user)
    today = Dates.today(zone)

    {:ok, task} =
      Tasks.create_task(
        user,
        %{
          title: "Both",
          due_at: Dates.from_local(today, nil, :due_at, zone),
          planned_at: Dates.from_local(today, nil, :planned_at, zone)
        },
        command()
      )

    {:ok, view, _html} = live(conn, ~p"/agenda")
    view |> element("#task-#{task.id} button[phx-click=complete]") |> render_click()

    assert has_element?(view, "#agenda-due #task-#{task.id}")
    refute has_element?(view, "#agenda-tasks #task-#{task.id}")
  end

  test "an empty agenda names the day", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/agenda")
    assert has_element?(view, "#agenda-empty", "Nothing planned or due today")
    assert has_element?(view, "#agenda-empty", "planned or due today to have it show up here")

    {:ok, view, _html} = live(conn, ~p"/agenda?date=2031-01-01")
    assert has_element?(view, "#agenda-empty", "Nothing planned or due Wednesday, 1 January 2031")
    assert has_element?(view, "#agenda-empty", "planned or due that day")
  end

  test "the inspector sets and clears dates in the user's zone", %{conn: conn, user: user} do
    {:ok, task} = Tasks.create_task(user, %{title: "Report", inbox: false}, command())

    {:ok, view, _html} = live(conn, ~p"/open")
    view |> element("#open-tasks li.task-row", "Report") |> render_click()

    commit = fn text ->
      view
      |> element("#inspector-task-dates-due")
      |> render_hook("date-commit", %{"key" => "due", "text" => text})
    end

    commit.("2026-10-02")
    assert Tasks.get_task(user, task.id).due_at == ~U[2026-10-02 15:00:00Z]
    assert has_element?(view, "#inspector-task-dates-due[value='2 Oct 2026, 17:00']")
    assert has_element?(view, "#open-tasks .mark--due")

    commit.("2026-10-02 08:15")
    assert Tasks.get_task(user, task.id).due_at == ~U[2026-10-02 06:15:00Z]

    commit.("")
    assert Tasks.get_task(user, task.id).due_at == nil
  end

  test "a typed date shows what it reads and saves on commit", %{conn: conn, user: user} do
    {:ok, task} = Tasks.create_task(user, %{title: "Report", inbox: false}, command())

    {:ok, view, _html} = live(conn, ~p"/open")
    view |> element("#open-tasks li.task-row", "Report") |> render_click()

    view
    |> form("#inspector-task", task: %{due_text: "24/12/2030 9:15"})
    |> render_change(%{"_target" => ["task", "due_text"]})

    assert has_element?(view, "#inspector-task-dates-due-reads", "24 December 2030")
    assert Tasks.get_task(user, task.id).due_at == nil

    view
    |> element("#inspector-task-dates-due")
    |> render_hook("date-commit", %{"key" => "due", "text" => "24/12/2030 9:15"})

    assert Tasks.get_task(user, task.id).due_at == ~U[2030-12-24 08:15:00Z]
    assert has_element?(view, "#inspector-task-dates-due[value='24 Dec 2030, 09:15']")
    refute has_element?(view, "#inspector-task-dates-due-reads", "24 December")
  end

  test "tonight is the field's evening", %{conn: conn, user: user} do
    {:ok, task} = Tasks.create_task(user, %{title: "Report", inbox: false}, command())

    {:ok, view, _html} = live(conn, ~p"/open")
    view |> element("#open-tasks li.task-row", "Report") |> render_click()

    for {key, field} <- [{"defer", :defer_until}, {"planned", :planned_at}, {"due", :due_at}] do
      view
      |> element("#inspector-task-dates-#{key}")
      |> render_hook("date-commit", %{"key" => key, "text" => "tue evening"})

      zone = Marskal.Accounts.timezone(user)
      {_date, time} = Tasks.get_task(user, task.id) |> Map.fetch!(field) |> Dates.to_local(zone)
      assert time == Dates.evening_time(field)
    end
  end

  test "an unreadable date is not saved", %{conn: conn, user: user} do
    due_at = ~U[2030-12-24 16:00:00Z]

    {:ok, task} =
      Tasks.create_task(user, %{title: "Report", inbox: false, due_at: due_at}, command())

    {:ok, view, _html} = live(conn, ~p"/open")
    view |> element("#open-tasks li.task-row", "Report") |> render_click()

    view
    |> element("#inspector-task-dates-due")
    |> render_hook("date-commit", %{"key" => "due", "text" => "someday soon"})

    assert has_element?(view, "#inspector-task-dates-due-reads.reads--error")

    assert has_element?(
             view,
             "#inspector-task-dates-due[aria-invalid='true'][value='someday soon']"
           )

    assert Tasks.get_task(user, task.id).due_at == due_at
  end

  test "a project's dates are typed the same way", %{conn: conn, user: user} do
    {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())

    {:ok, view, _html} = live(conn, ~p"/open?project=#{project.id}")

    view
    |> element("#inspector-project-dates-planned")
    |> render_hook("date-commit", %{"key" => "planned", "text" => "2031-03-01"})

    assert Projects.get_project(user, project.id).planned_at == ~U[2031-03-01 08:00:00Z]
  end

  test "Danish words are read with a Danish locale", %{conn: conn, user: user} do
    {:ok, task} = Tasks.create_task(user, %{title: "Report", inbox: false}, command())

    {:ok, view, _html} = live(conn, ~p"/open")
    view |> element("#open-tasks li.task-row", "Report") |> render_click()

    view
    |> element("#inspector-task-dates-planned")
    |> render_hook("date-commit", %{"key" => "planned", "text" => "i morgen"})

    assert Tasks.get_task(user, task.id).planned_at == nil

    {:ok, _} = Marskal.Accounts.update_preferences(user, %{locale: "da"}, command())
    {:ok, view, _html} = live(conn, ~p"/open")
    view |> element("#open-tasks li.task-row", "Report") |> render_click()

    view
    |> element("#inspector-task-dates-planned")
    |> render_hook("date-commit", %{"key" => "planned", "text" => "i morgen"})

    zone = Marskal.Accounts.timezone(user)
    tomorrow = zone |> Dates.today() |> Date.add(1)

    assert Tasks.get_task(user, task.id).planned_at ==
             Dates.from_local(tomorrow, nil, :planned_at, zone)
  end

  test "the calendar picks a day and keeps the stored time", %{conn: conn, user: user} do
    due_at = ~U[2030-12-24 08:15:00Z]

    {:ok, task} =
      Tasks.create_task(user, %{title: "Report", inbox: false, due_at: due_at}, command())

    {:ok, view, _html} = live(conn, ~p"/open")
    view |> element("#open-tasks li.task-row", "Report") |> render_click()

    view |> element("#inspector-task-dates-due-calendar-toggle") |> render_click()
    assert has_element?(view, "#inspector-task-dates-due-calendar", "December 2030")

    assert has_element?(
             view,
             "#inspector-task-dates-due-calendar-2030-12-24.calendar__day--selected"
           )

    view |> element("#inspector-task-dates-due-calendar-next") |> render_click()
    assert has_element?(view, "#inspector-task-dates-due-calendar", "January 2031")

    view |> element("#inspector-task-dates-due-calendar-2031-01-07") |> render_click()

    assert Tasks.get_task(user, task.id).due_at == ~U[2031-01-07 08:15:00Z]
    refute has_element?(view, "#inspector-task-dates-due-calendar")
    assert has_element?(view, "#inspector-task-dates-due[value='7 Jan 2031, 09:15']")
  end

  test "the calendar starts on the user's week start, at this month", %{
    conn: conn,
    user: user
  } do
    {:ok, _} = Marskal.Accounts.update_preferences(user, %{week_start: 7}, command())
    {:ok, _task} = Tasks.create_task(user, %{title: "Report", inbox: false}, command())

    {:ok, view, _html} = live(conn, ~p"/open")
    view |> element("#open-tasks li.task-row", "Report") |> render_click()
    view |> element("#inspector-task-dates-planned-calendar-toggle") |> render_click()

    today = user |> Marskal.Accounts.timezone() |> Dates.today()
    assert has_element?(view, "#inspector-task-dates-planned-calendar th:first-child", "Sun")

    assert has_element?(
             view,
             "#inspector-task-dates-planned-calendar-#{today}.calendar__day--today"
           )

    view |> element("#inspector-task-dates-planned-calendar-toggle") |> render_click()
    refute has_element?(view, "#inspector-task-dates-planned-calendar")
  end

  test "deferring from the inspector hides the task from the open stream", %{
    conn: conn,
    user: user
  } do
    {:ok, task} = Tasks.create_task(user, %{title: "Paint", inbox: false}, command())

    {:ok, view, _html} = live(conn, ~p"/open")
    view |> element("#open-tasks li.task-row", "Paint") |> render_click()
    assert has_element?(view, "#inspector-task-dates-defer")

    view
    |> form("#inspector-task", task: %{deferred_indefinitely: "true"})
    |> render_change()

    assert Tasks.get_task(user, task.id).deferred_indefinitely
    refute has_element?(view, "#inspector-task-dates-defer")
    refute has_element?(view, "#inspector-task-dates-defer-calendar-toggle")

    {:ok, view, _html} = live(conn, ~p"/open")
    refute has_element?(view, "#open-tasks", "Paint")

    view |> element("#visibility-deferred") |> render_click()
    render(view)
    assert has_element?(view, "#open-tasks li.is-unavailable .mark--deferred", "Deferred")
  end

  test "a task and a project can be deleted from the inspector", %{conn: conn, user: user} do
    {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())
    {:ok, task} = Tasks.create_task(user, %{title: "Dig", project_id: project.id}, command())

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}?task=#{task.id}")
    view |> element("#inspector-task-delete") |> render_click()

    assert Tasks.get_task(user, task.id) == nil
    refute has_element?(view, "#project-tasks", "Dig")

    {:ok, view, _html} = live(conn, ~p"/open?project=#{project.id}")
    view |> element("#inspector-project-delete") |> render_click()
    assert Projects.get_project(user, project.id) == nil
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
