defmodule MarskalWeb.AppShellLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  test "the tab bar marks the current view", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    {:ok, view, _html} = live(conn, ~p"/agenda")

    assert has_element?(view, ".tab-bar a[aria-current=page]", "Agenda")
    refute has_element?(view, ".tab-bar a[aria-current=page]", "Inbox")

    {:ok, view, _html} = live(conn, ~p"/flagged")
    assert has_element?(view, ".tab-bar a[aria-current=page]", "Flagged")

    {:ok, view, _html} = live(conn, ~p"/open")
    assert has_element?(view, ".tab-bar a[aria-current=page]", "Open")
    assert has_element?(view, ~s(.tab-bar a[href="/open"]))
  end

  test "the logo opens the home view", %{conn: conn} do
    user = user_fixture()

    {:ok, _} =
      Marskal.Accounts.update_preferences(
        user,
        %{home_view: :flagged},
        Ecto.UUID.generate(version: 7)
      )

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/inbox")
    assert has_element?(view, ~s(.app-header__brand a[href="/flagged"]))
  end

  test "the sidebar holds the account links for the phone drawer", %{conn: conn} do
    user = user_fixture()
    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/open")

    assert has_element?(view, ".app-header__menu[aria-controls=sidebar]")
    assert has_element?(view, "#sidebar .sidebar-account", user.email)
    assert has_element?(view, ~s|#sidebar .sidebar-account a[href="/users/settings"]|)
  end

  test "a project page opened alone has a button to show its details", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, project} =
      Marskal.Projects.create_project(
        user,
        %{"title" => "Launch"},
        Ecto.UUID.generate(version: 7)
      )

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    assert has_element?(view, ".app-inspector__title", "Details")
    refute has_element?(view, "#inspector-project-title")

    view |> element(".page-heading__details") |> render_click()

    assert_patch(view, ~p"/projects/#{project.id}?#{[project: project.id]}")
    assert has_element?(view, ".app-inspector__title", "Project")
    assert has_element?(view, "#inspector-project-title[value='Launch']")
    refute has_element?(view, ".page-heading__details")
  end

  test "record links say they open the inspector, for the client to skip", %{conn: conn} do
    user = user_fixture()

    {:ok, _project} =
      Marskal.Projects.create_project(
        user,
        %{"title" => "Launch"},
        Ecto.UUID.generate(version: 7)
      )

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/open")

    assert has_element?(view, "#sidebar a[data-opens-inspector]", "Launch")
  end

  test "quick capture adds a task to the inbox from another page", %{conn: conn} do
    user = user_fixture()
    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/agenda")

    view
    |> form("#quick-capture-form", task: %{title: "Call the plumber"})
    |> render_submit()

    assert [%{title: "Call the plumber", inbox: true}] = Marskal.Tasks.list_inbox(user)
    assert render(view) =~ "Added to the inbox."
    assert has_element?(view, "#flash-info.toast--info[role=status]")
    assert has_element?(view, "#quick-capture-title[value='']")
  end

  test "the inbox page has its own capture form instead", %{conn: conn} do
    {:ok, view, _html} = live(log_in_user(conn, user_fixture()), ~p"/inbox")

    refute has_element?(view, "#quick-capture")
  end

  test "Escape closes a sidebar add field", %{conn: conn} do
    {:ok, view, _html} = live(log_in_user(conn, user_fixture()), ~p"/open")

    view |> element("button[aria-label='New folder']") |> render_click()
    assert has_element?(view, "#new-root-folder input[placeholder='New folder']")

    view |> element("#new-root-folder") |> render_keydown(%{"key" => "Escape"})
    refute has_element?(view, "#new-root-folder")
    assert has_element?(view, "button[aria-label='New folder'][aria-expanded=false]")
  end

  test "signed-out pages have no menu or tab bar", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    refute has_element?(view, ".app-header__menu")
    refute has_element?(view, ".tab-bar")
  end
end
