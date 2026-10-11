defmodule MarskalWeb.InspectorLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  alias Marskal.ProjectFolders
  alias Marskal.Projects
  alias Marskal.Tasks

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "the open page shows an empty inspector", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Select a task, project, folder, or tag to edit."
    assert html =~ "app-inspector"
  end

  test "the inspector sets a task's URL, and says why it refuses one", %{conn: conn, user: user} do
    {:ok, task} = Tasks.create_task(user, %{"title" => "Fix", "inbox" => false}, command())

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#open-tasks li.task-row", "Fix") |> render_click()

    view |> form("#inspector-task", task: %{url: "https://jira.example/X-1"}) |> render_change()

    assert Tasks.get_task(user, task.id).url == "https://jira.example/X-1"
    assert has_element?(view, "#open-tasks a.url-link[href='https://jira.example/X-1']")

    view |> form("#inspector-task", task: %{url: "javascript:alert(1)"}) |> render_change()

    assert render(view) =~ "URL cannot use that scheme."
    assert Tasks.get_task(user, task.id).url == "https://jira.example/X-1"
  end

  test "a task can be edited from the list and the inspector closed", %{conn: conn, user: user} do
    {:ok, task} = Tasks.create_task(user, %{"title" => "Milk", "inbox" => false}, command())

    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#inspector-task")

    view |> element("#open-tasks li.task-row", "Milk") |> render_click()

    assert has_element?(view, "#inspector-task")
    assert has_element?(view, "#open-tasks li.is-selected", "Milk")
    assert has_element?(view, "#inspector-task-title[value='Milk']")
    assert has_element?(view, "#inspector-task option[value='to_do'][selected]")

    view
    |> form("#inspector-task", task: %{title: "Oat milk", notes: "Buy **oat**"})
    |> render_change()

    assert has_element?(view, "#open-tasks", "Oat milk")
    assert has_element?(view, "#inspector-task-title[value='Oat milk']")
    assert has_element?(view, "#inspector-task-notes", "Buy **oat**")
    assert Tasks.get_task(user, task.id).title == "Oat milk"
    assert Tasks.get_task(user, task.id).notes == "Buy **oat**"

    view |> element("button[aria-label='Close inspector']") |> render_click()

    refute has_element?(view, "#inspector-task")
    refute has_element?(view, "#open-tasks li.is-selected")
    assert render(view) =~ "Select a task, project, folder, or tag to edit."
  end

  test "a done task keeps its row; a moved one leaves at once", %{
    conn: conn,
    user: user
  } do
    {:ok, _} = Tasks.create_task(user, %{"title" => "Milk", "inbox" => false}, command())

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#open-tasks li.task-row", "Milk") |> render_click()
    view |> form("#inspector-task", task: %{state: "done"}) |> render_change()

    assert has_element?(view, "#open-tasks li.is-resolved", "Milk")
    assert has_element?(view, "#inspector-task option[value='done'][selected]")

    {:ok, inbox} = Tasks.create_task(user, %{"title" => "Bread"}, command())
    {:ok, inbox_view, _html} = live(conn, ~p"/inbox")
    inbox_view |> element("#inbox-tasks li.task-row", "Bread") |> render_click()
    inbox_view |> form("#inspector-task", task: %{location: "none"}) |> render_change()

    refute has_element?(inbox_view, "#inbox-tasks", "Bread")
    assert Tasks.get_task(user, inbox.id).inbox == false

    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#open-tasks", "Milk")
  end

  test "a direct link opens the task, and someone else's task does not", %{conn: conn, user: user} do
    {:ok, task} = Tasks.create_task(user, %{"title" => "Secret", "inbox" => false}, command())

    {:ok, view, _html} = live(conn, "/?task=#{task.id}")
    assert has_element?(view, "#inspector-task-title[value='Secret']")

    other = log_in_user(build_conn(), user_fixture())
    {:ok, _other_view, html} = live(other, "/?task=#{task.id}")
    assert html =~ "That item is not available."
    refute html =~ "Secret"
  end

  test "clearing a title does not rename the task", %{conn: conn, user: user} do
    {:ok, task} = Tasks.create_task(user, %{"title" => "Milk", "inbox" => false}, command())

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#open-tasks li.task-row", "Milk") |> render_click()
    html = view |> form("#inspector-task", task: %{title: ""}) |> render_change()

    refute html =~ "Could not save this task."
    refute html =~ ">Save<"
    assert Tasks.get_task(user, task.id).title == "Milk"
    assert has_element?(view, "#open-tasks", "Milk")
  end

  test "a project can be renamed, filed, and completed from the sidebar", %{
    conn: conn,
    user: user
  } do
    {:ok, folder} = ProjectFolders.create_folder(user, %{"name" => "Work"}, command())
    {:ok, project} = Projects.create_project(user, %{"title" => "Launch"}, command())

    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, view, _html} =
      view |> element("#sidebar a", "Launch") |> render_click() |> follow_redirect(conn)

    assert has_element?(view, "#sidebar a.is-current", "Launch")
    assert has_element?(view, "#inspector-project-title[value='Launch']")

    view |> form("#inspector-project", project: %{title: "Launch site"}) |> render_change()
    assert has_element?(view, "#sidebar", "Launch site")

    view
    |> form("#inspector-project", project: %{project_folder_id: folder.id})
    |> render_change()

    assert Projects.get_project(user, project.id).project_folder_id == folder.id

    view |> form("#inspector-project", project: %{state: "done"}) |> render_change()
    refute has_element?(view, "#sidebar a", "Launch site")
    assert has_element?(view, "#inspector-project option[value='done'][selected]")
  end

  test "clicking the current page in the sidebar only moves the inspector", %{
    conn: conn,
    user: user
  } do
    {:ok, project} = Projects.create_project(user, %{"title" => "Launch"}, command())

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}?#{[project: project.id]}")
    view |> element("#sidebar a", "Launch") |> render_click()

    assert_patch(view, ~p"/projects/#{project.id}?#{[project: project.id]}")
    assert has_element?(view, "#inspector-project-title[value='Launch']")
  end

  test "a project on a folder page opens with the inspector on it", %{conn: conn, user: user} do
    {:ok, folder} = ProjectFolders.create_folder(user, %{"name" => "Work"}, command())

    {:ok, project} =
      Projects.create_project(
        user,
        %{"title" => "Launch", "project_folder_id" => folder.id},
        command()
      )

    {:ok, view, _html} = live(conn, ~p"/folders/#{folder.id}")

    {:ok, view, _html} =
      view |> element(".app-main a", "Launch") |> render_click() |> follow_redirect(conn)

    assert has_element?(view, "#sidebar a.is-current", "Launch")
    assert has_element?(view, "#inspector-project-title[value='Launch']")
    assert Projects.get_project(user, project.id).title == "Launch"
  end

  test "a folder can be renamed, and its parent list excludes itself and its children", %{
    conn: conn,
    user: user
  } do
    {:ok, work} = ProjectFolders.create_folder(user, %{"name" => "Work"}, command())

    {:ok, child} =
      ProjectFolders.create_folder(user, %{"name" => "Child", "parent_id" => work.id}, command())

    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, view, _html} =
      view |> element("#sidebar a", "Work") |> render_click() |> follow_redirect(conn)

    assert has_element?(view, "#inspector-folder-name[value='Work']")
    refute has_element?(view, "#inspector-folder-parent option[value='#{work.id}']")
    refute has_element?(view, "#inspector-folder-parent option[value='#{child.id}']")

    {:ok, view, _html} =
      view |> element("#sidebar a", "Child") |> render_click() |> follow_redirect(conn)

    assert has_element?(view, "#inspector-folder-parent option[value='#{work.id}']")
    refute has_element?(view, "#inspector-folder-parent option[value='#{child.id}']")

    view |> form("#inspector-folder", project_folder: %{name: "Studio"}) |> render_change()
    assert has_element?(view, "#sidebar", "Studio")
    assert ProjectFolders.get_folder(user, child.id).name == "Studio"
  end

  test "a save error names the field", %{conn: conn, user: user} do
    {:ok, task} = Tasks.create_task(user, %{"title" => "Milk", "inbox" => false}, command())

    {:ok, view, _html} = live(conn, "/?task=#{task.id}")

    html =
      view
      |> form("#inspector-task", task: %{title: String.duplicate("a", 501)})
      |> render_change()

    assert html =~ "Title should be at most 500 character(s)."
    assert Tasks.get_task(user, task.id).title == "Milk"
  end

  test "a malformed id is not available instead of a crash", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/?task=not-a-uuid")
    assert html =~ "That item is not available."

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/projects/not-a-uuid")
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/folders/not-a-uuid")
  end

  test "a change made elsewhere shows on the page and in the inspector", %{
    conn: conn,
    user: user
  } do
    {:ok, task} = Tasks.create_task(user, %{"title" => "Milk", "inbox" => false}, command())
    {:ok, view, _html} = live(conn, "/?task=#{task.id}")

    {:ok, _} = Tasks.rename_task(user, task.id, "Oat milk", command())
    {:ok, _} = Projects.create_project(user, %{"title" => "Launch"}, command())

    assert has_element?(view, "#open-tasks", "Oat milk")
    assert has_element?(view, "#inspector-task-title[value='Oat milk']")
    assert has_element?(view, "#sidebar", "Launch")
    assert has_element?(view, "#inspector-task-location option", "Launch")
  end

  test "a flag set in the inspector puts a task in Flagged, and a project flags its tasks", %{
    conn: conn,
    user: user
  } do
    {:ok, project} = Projects.create_project(user, %{"title" => "Home"}, command())

    {:ok, _} =
      Tasks.create_task(user, %{"title" => "Call", "project_id" => project.id}, command())

    {:ok, _} =
      Tasks.create_task(user, %{"title" => "Paint", "project_id" => project.id}, command())

    {:ok, view, _html} = live(conn, ~p"/flagged")
    assert render(view) =~ "Nothing flagged."

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#open-tasks li.task-row", "Call") |> render_click()
    view |> form("#inspector-task", task: %{flagged: "true"}) |> render_change()

    assert has_element?(view, "#open-tasks li.task-row:has(.mark--flag[title='Flagged'])", "Call")
    refute has_element?(view, "#open-tasks li.task-row:has(.mark--flag)", "Paint")

    {:ok, view, _html} = live(conn, ~p"/flagged")
    assert has_element?(view, "#flagged-tasks li.task-row", "Call")
    refute has_element?(view, "#flagged-tasks li.task-row", "Paint")

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}?#{[project: project.id]}")
    view |> form("#inspector-project", project: %{flagged: "true"}) |> render_change()

    {:ok, view, _html} = live(conn, ~p"/flagged")
    assert has_element?(view, "#flagged-tasks li.task-row", "Call")

    assert has_element?(
             view,
             "#flagged-tasks li.task-row:has(.mark--flag[title='Flagged by its project'])",
             "Paint"
           )

    view |> element("#flagged-tasks li.task-row", "Paint") |> render_click()
    assert has_element?(view, "#inspector-task-flagged-by-project")
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
