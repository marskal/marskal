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

    assert has_element?(view, "#visibility", "Also show")
    assert has_element?(view, "#visibility", "To-do items stay listed.")
    assert has_element?(view, "#visibility-all", "All of these")
    assert has_element?(view, "#visibility-none", "None of these")
    assert has_element?(view, "#visibility-none[disabled]")
    refute has_element?(view, "#visibility-all[disabled]")
    refute has_element?(view, "#sidebar-projects", "Finished")
    refute has_element?(view, "#sidebar-projects", "Later")
    refute has_element?(view, "#sidebar-projects", "Parked")
    refute has_element?(view, "#sidebar-projects", "Old files")
    refute has_element?(view, "#sidebar-tags", "Retired")
    refute has_element?(view, "#project-tasks", "File")
    assert has_element?(view, "#project-resolved", "This project is done")

    view |> element("#visibility-done") |> render_click()
    render(view)

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
    assert has_element?(view, "#visibility-all[disabled]")

    view |> element("#visibility-none") |> render_click()
    render(view)

    refute has_element?(view, "#sidebar-projects", "Finished")
    refute has_element?(view, "#sidebar-projects", "Later")
    refute has_element?(view, "#sidebar-projects", "Parked")
    refute has_element?(view, "#project-tasks", "File")
    assert has_element?(view, "#visibility-none[disabled]")
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
    assert has_element?(view, "#project-hidden", "Nothing to show.")
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

    conn = conn |> put_req_cookie("marskal_visibility", "done") |> get(~p"/open")
    {:ok, view, _html} = live(conn)

    assert has_element?(view, "#visibility-done[checked]")
    assert has_element?(view, "#sidebar-projects", "Finished")
  end

  test "moving to another page keeps the choice", %{conn: conn, user: user} do
    {:ok, finished} = Projects.create_project(user, %{title: "Finished"}, command())
    {:ok, _} = Projects.complete_project(user, finished.id, command())

    conn = get(conn, ~p"/open")
    {:ok, view, _html} = live(conn)
    refute has_element?(view, "#sidebar-projects", "Finished")

    view |> element("#visibility-done") |> render_click()
    render(view)
    assert has_element?(view, "#sidebar-projects", "Finished")

    {:ok, inbox, _html} =
      view
      |> element("#sidebar a", "Inbox")
      |> render_click()
      |> follow_redirect(conn, ~p"/inbox")

    assert has_element?(inbox, "#sidebar-projects", "Finished")
    assert has_element?(inbox, "#visibility-done[checked]")
  end

  test "posting the choice stores it on the cookie, not on the user", %{conn: conn} do
    conn = post(conn, ~p"/visibility", %{"value" => "done,dropped"})

    assert conn.status == 204
    assert conn.resp_cookies["marskal_visibility"].value == "done,dropped"
    assert get_session(conn, "visibility") == "done,dropped"
  end

  test "signed-out pages omit the control" do
    {:ok, view, _html} = live(build_conn(), ~p"/users/log-in")

    refute has_element?(view, "#visibility")
    assert has_element?(view, "#theme-toggle")
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
