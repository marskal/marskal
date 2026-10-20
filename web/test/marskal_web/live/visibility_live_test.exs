defmodule MarskalWeb.VisibilityLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  alias Marskal.ProjectFolders
  alias Marskal.Projects
  alias Marskal.Tags
  alias Marskal.Tasks

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "the header chooses Done, Dropped, and Deferred, defaulting to none", %{
    conn: conn,
    user: user
  } do
    {:ok, finished} = Projects.create_project(user, %{title: "Finished"}, command())
    {:ok, _} = Projects.complete_project(user, finished.id, command())
    {:ok, task} = Tasks.create_task(user, %{title: "File", project_id: finished.id}, command())
    {:ok, _} = Tasks.complete_task(user, task.id, command())

    {:ok, _later} =
      Projects.create_project(user, %{title: "Later", deferred_indefinitely: true}, command())

    {:ok, parked} = Projects.create_project(user, %{title: "Parked"}, command())
    {:ok, _} = Projects.drop_project(user, parked.id, command())

    {:ok, folder} = ProjectFolders.create_folder(user, %{name: "Old files"}, command())
    {:ok, _} = ProjectFolders.drop_folder(user, folder.id, command())

    {:ok, tag} = Tags.create_tag(user, %{name: "Retired"}, command())
    {:ok, _} = Tags.set_tag_state(user, tag.id, :dropped, command())

    {:ok, view, _html} = live(conn, ~p"/projects/#{finished.id}")

    assert has_element?(view, "#visibility", "Show")

    for kind <- ~w(done dropped deferred) do
      assert has_element?(view, "#visibility-#{kind}[aria-pressed=false]")
    end

    refute has_element?(view, "#sidebar-projects", "Finished")
    refute has_element?(view, "#sidebar-projects", "Later")
    refute has_element?(view, "#sidebar-projects", "Parked")
    refute has_element?(view, "#sidebar-projects", "Old files")
    refute has_element?(view, "#sidebar-tags", "Retired")
    refute has_element?(view, "#project-tasks", "File")
    assert has_element?(view, "#project-resolved", "This project is done")

    view |> element("#visibility-done") |> render_click()
    render(view)

    assert_push_event(view, "visibility", %{value: "done"})
    assert has_element?(view, "#visibility-done[aria-pressed=true]")
    assert has_element?(view, "#sidebar-projects li.is-done", "Finished")
    assert has_element?(view, "#project-tasks li.is-resolved", "File")
    refute has_element?(view, "#project-resolved")
    refute has_element?(view, "#sidebar-projects", "Parked")

    view |> element("#visibility-dropped") |> render_click()
    render(view)

    assert has_element?(view, "#sidebar-projects li.is-dropped", "Parked")
    assert has_element?(view, "#sidebar-projects li.is-dropped", "Old files")
    assert has_element?(view, "#sidebar-tags li.is-dropped", "Retired")

    view |> element("#visibility-deferred") |> render_click()
    render(view)

    assert has_element?(view, "#sidebar-projects li.is-deferred", "Later")
    assert_push_event(view, "visibility", %{value: "done,dropped,deferred"})

    for kind <- ~w(done dropped deferred) do
      view |> element("#visibility-#{kind}") |> render_click()
    end

    render(view)

    refute has_element?(view, "#sidebar-projects", "Finished")
    refute has_element?(view, "#sidebar-projects", "Later")
    refute has_element?(view, "#sidebar-projects", "Parked")
    refute has_element?(view, "#project-tasks", "File")
    assert_push_event(view, "visibility", %{value: ""})
  end

  test "a deferred to-do task is hidden until Deferred is on", %{conn: conn, user: user} do
    {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())

    {:ok, _} =
      Tasks.create_task(
        user,
        %{title: "Dig", project_id: project.id, deferred_indefinitely: true},
        command()
      )

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    assert has_element?(view, "#sidebar-projects", "Garden")
    refute has_element?(view, "#project-tasks", "Dig")
    assert has_element?(view, "#project-hidden", "Its tasks still to do are deferred.")
    refute has_element?(view, "#project-finished")
    refute has_element?(view, "#project-empty")

    view |> element("#visibility-deferred") |> render_click()
    render(view)

    assert has_element?(view, "#project-tasks", "Dig")
    refute has_element?(view, "#project-hidden")
  end

  test "a cookie brings the choice back on the next full load", %{conn: conn, user: user} do
    {:ok, finished} = Projects.create_project(user, %{title: "Finished"}, command())
    {:ok, _} = Projects.complete_project(user, finished.id, command())

    conn = conn |> put_req_cookie("marskal_show", "done") |> get(~p"/open")
    assert html_response(conn, 200) =~ "Finished"
    {:ok, view, _html} = live(conn)

    assert has_element?(view, "#visibility-done[aria-pressed=true]")
    assert has_element?(view, "#sidebar-projects", "Finished")
  end

  # The browser sends the cookie as it is now on every live mount, so a
  # page reached by live navigation agrees with a toggle made since.
  test "a live mount goes by the browser's connect param", %{conn: conn, user: user} do
    {:ok, finished} = Projects.create_project(user, %{title: "Finished"}, command())
    {:ok, _} = Projects.complete_project(user, finished.id, command())

    {:ok, view, _html} =
      conn
      |> put_req_cookie("marskal_show", "dropped")
      |> put_connect_params(%{"show" => "done"})
      |> live(~p"/inbox")

    assert has_element?(view, "#sidebar-projects", "Finished")
    assert has_element?(view, "#visibility-done[aria-pressed=true]")
    assert has_element?(view, "#visibility-dropped[aria-pressed=false]")
  end

  test "another tab's choice applies without storing it again", %{conn: conn, user: user} do
    {:ok, finished} = Projects.create_project(user, %{title: "Finished"}, command())
    {:ok, _} = Projects.complete_project(user, finished.id, command())

    {:ok, view, _html} = live(conn, ~p"/open")
    refute has_element?(view, "#sidebar-projects", "Finished")

    render_hook(view, "visibility", %{"value" => "done"})

    assert has_element?(view, "#sidebar-projects", "Finished")
    refute_push_event(view, "visibility", %{})
  end

  test "a toggle renders the reloaded list, not an empty one first", %{conn: conn, user: user} do
    zone = Marskal.Accounts.timezone(user)
    due = Marskal.Dates.from_local(Marskal.Dates.today(zone), nil, :due_at, zone)
    {:ok, _} = Tasks.create_task(user, %{title: "Pay rent", due_at: due}, command())

    {:ok, view, _html} = live(conn, ~p"/agenda")

    for _ <- 1..2 do
      html = view |> element("#visibility-done") |> render_click()
      assert html =~ "Pay rent"
      refute html =~ ~s(id="agenda-empty")
    end
  end

  test "today's agenda carries over what is open or was resolved today", %{
    conn: conn,
    user: user
  } do
    zone = Marskal.Accounts.timezone(user)
    today = Marskal.Dates.today(zone)
    due = fn date -> Marskal.Dates.from_local(date, nil, :due_at, zone) end
    planned = fn date -> Marskal.Dates.from_local(date, nil, :planned_at, zone) end
    earlier = Date.add(today, -3)

    resolve = fn attrs, state, at ->
      {:ok, task} = Tasks.create_task(user, attrs, command())
      {:ok, _} = Tasks.update_task(user, task.id, %{state: state}, command(), at: at)
    end

    now = DateTime.utc_now(:second)
    # Within the 48 hours a client may backdate, and never today.
    long_ago = DateTime.add(now, -36 * 3600)

    resolve.(%{title: "Paid today", due_at: due.(today)}, :done, now)
    resolve.(%{title: "Paid late, today", due_at: due.(earlier)}, :done, now)
    resolve.(%{title: "Skipped late, today", planned_at: planned.(earlier)}, :dropped, now)
    resolve.(%{title: "Paid long ago", due_at: due.(earlier)}, :done, long_ago)
    resolve.(%{title: "Swept long ago", planned_at: planned.(earlier)}, :done, long_ago)

    {:ok, _} =
      Tasks.create_task(user, %{title: "Still overdue", due_at: due.(earlier)}, command())

    {:ok, finished} = Projects.create_project(user, %{title: "Finished"}, command())
    {:ok, _} = Projects.complete_project(user, finished.id, command())

    {:ok, _} =
      Tasks.create_task(
        user,
        %{title: "Under finished", project_id: finished.id, due_at: due.(earlier)},
        command()
      )

    {:ok, view, _html} = live(conn, ~p"/agenda")
    view |> element("#visibility-done") |> render_click()
    view |> element("#visibility-dropped") |> render_click()

    assert has_element?(view, "#agenda-due, #agenda-tasks", "Paid today")
    assert has_element?(view, "#agenda-due, #agenda-tasks", "Still overdue")
    assert has_element?(view, "#agenda-due", "Paid late, today")
    assert has_element?(view, "#agenda-tasks", "Skipped late, today")
    refute has_element?(view, "#agenda-due, #agenda-tasks", "Paid long ago")
    refute has_element?(view, "#agenda-due, #agenda-tasks", "Swept long ago")
    refute has_element?(view, "#agenda-due, #agenda-tasks", "Under finished")
  end

  test "signed-out pages omit the control" do
    {:ok, view, _html} = live(build_conn(), ~p"/users/log-in")

    refute has_element?(view, "#visibility")
    assert has_element?(view, "#theme-toggle")
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
