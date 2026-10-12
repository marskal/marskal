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
    assert has_element?(view, "#agenda-empty", "Nothing planned or due Wednesday 1 January 2031")
    assert has_element?(view, "#agenda-empty", "planned or due that day")
  end

  test "the inspector sets and clears dates in the user's zone", %{conn: conn, user: user} do
    {:ok, task} = Tasks.create_task(user, %{title: "Report", inbox: false}, command())

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#open-tasks li.task-row", "Report") |> render_click()

    view
    |> form("#inspector-task", task: %{due_date: "2026-10-02"})
    |> render_change()

    assert Tasks.get_task(user, task.id).due_at == ~U[2026-10-02 15:00:00Z]
    assert has_element?(view, "#inspector-task-dates-due-time[value='17:00']")
    assert has_element?(view, "#open-tasks .mark--due")

    view
    |> form("#inspector-task", task: %{due_date: "2026-10-02", due_time: "08:15"})
    |> render_change()

    assert Tasks.get_task(user, task.id).due_at == ~U[2026-10-02 06:15:00Z]

    view |> form("#inspector-task", task: %{due_date: ""}) |> render_change()
    assert Tasks.get_task(user, task.id).due_at == nil
  end

  test "deferring from the inspector hides the task from the open stream", %{
    conn: conn,
    user: user
  } do
    {:ok, task} = Tasks.create_task(user, %{title: "Paint", inbox: false}, command())

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#open-tasks li.task-row", "Paint") |> render_click()

    view
    |> form("#inspector-task", task: %{deferred_indefinitely: "true"})
    |> render_change()

    assert Tasks.get_task(user, task.id).deferred_indefinitely

    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#open-tasks", "Paint")

    {:ok, view, _html} = live(conn, ~p"/?unavailable=1")
    assert has_element?(view, "#open-tasks li.is-unavailable .mark--deferred", "Deferred")
  end

  test "a task and a project can be deleted from the inspector", %{conn: conn, user: user} do
    {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())
    {:ok, task} = Tasks.create_task(user, %{title: "Dig", project_id: project.id}, command())

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}?task=#{task.id}")
    view |> element("#inspector-task-delete") |> render_click()

    assert Tasks.get_task(user, task.id) == nil
    refute has_element?(view, "#project-tasks", "Dig")

    {:ok, view, _html} = live(conn, ~p"/?project=#{project.id}")
    view |> element("#inspector-project-delete") |> render_click()
    assert Projects.get_project(user, project.id) == nil
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
