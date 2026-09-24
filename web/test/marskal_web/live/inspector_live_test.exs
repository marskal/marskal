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
    assert html =~ "Select a task, project, or folder to edit."
    assert html =~ "app-inspector"
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
    assert render(view) =~ "Select a task, project, or folder to edit."
  end

  test "changing state and inbox moves the task out of the current list", %{
    conn: conn,
    user: user
  } do
    {:ok, _} = Tasks.create_task(user, %{"title" => "Milk", "inbox" => false}, command())

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#open-tasks li.task-row", "Milk") |> render_click()
    view |> form("#inspector-task", task: %{state: "done"}) |> render_change()

    refute has_element?(view, "#open-tasks", "Milk")
    assert has_element?(view, "#inspector-task option[value='done'][selected]")

    {:ok, inbox} = Tasks.create_task(user, %{"title" => "Bread"}, command())
    {:ok, inbox_view, _html} = live(conn, ~p"/inbox")
    inbox_view |> element("#inbox-tasks li.task-row", "Bread") |> render_click()
    inbox_view |> form("#inspector-task", task: %{inbox: "false"}) |> render_change()

    refute has_element?(inbox_view, "#inbox-tasks", "Bread")
    assert Tasks.get_task(user, inbox.id).inbox == false
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

  test "saving in the inspector updates the task page form", %{conn: conn, user: user} do
    {:ok, task} = Tasks.create_task(user, %{"title" => "Milk", "inbox" => false}, command())

    {:ok, view, _html} = live(conn, "/tasks/#{task.id}?task=#{task.id}")
    view |> form("#inspector-task", task: %{title: "Oat milk"}) |> render_change()

    assert has_element?(view, "#task-form input[value='Oat milk']")
    assert Tasks.get_task(user, task.id).title == "Oat milk"
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
    view |> element("#sidebar button.select", "Launch") |> render_click()

    assert has_element?(view, "#inspector-project-title[value='Launch']")
    assert has_element?(view, "a", "Open project")

    view |> form("#inspector-project", project: %{title: "Launch site"}) |> render_change()
    assert has_element?(view, "#sidebar", "Launch site")

    view
    |> form("#inspector-project", project: %{project_folder_id: folder.id})
    |> render_change()

    assert Projects.get_project(user, project.id).project_folder_id == folder.id

    view |> form("#inspector-project", project: %{state: "done"}) |> render_change()
    refute has_element?(view, "#sidebar button.select", "Launch site")
    assert has_element?(view, "#inspector-project option[value='done'][selected]")
  end

  test "a folder can be renamed, and its parent list excludes itself and its children", %{
    conn: conn,
    user: user
  } do
    {:ok, work} = ProjectFolders.create_folder(user, %{"name" => "Work"}, command())

    {:ok, child} =
      ProjectFolders.create_folder(user, %{"name" => "Child", "parent_id" => work.id}, command())

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#sidebar button.select", "Work") |> render_click()

    assert has_element?(view, "#inspector-folder-name[value='Work']")
    assert has_element?(view, "a", "Open folder")
    refute has_element?(view, "#inspector-folder-parent option[value='#{work.id}']")
    refute has_element?(view, "#inspector-folder-parent option[value='#{child.id}']")

    view |> element("#sidebar button.select", "Child") |> render_click()
    assert has_element?(view, "#inspector-folder-parent option[value='#{work.id}']")
    refute has_element?(view, "#inspector-folder-parent option[value='#{child.id}']")

    view |> form("#inspector-folder", project_folder: %{name: "Studio"}) |> render_change()
    assert has_element?(view, "#sidebar", "Studio")
    assert ProjectFolders.get_folder(user, child.id).name == "Studio"
  end

  defp command, do: Ecto.UUID.generate()
end
