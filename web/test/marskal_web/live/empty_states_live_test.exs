defmodule MarskalWeb.EmptyStatesLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  alias Marskal.Projects
  alias Marskal.Tasks

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "each list says what would fill it", %{conn: conn} do
    for {path, id} <- [
          {~p"/inbox", "#inbox-empty"},
          {~p"/open", "#open-empty"},
          {~p"/flagged", "#flagged-empty"},
          {~p"/agenda", "#agenda-empty"},
          {~p"/tags/untagged", "#untagged-empty"}
        ] do
      {:ok, view, _html} = live(conn, path)
      assert has_element?(view, id), "no #{id} on #{path}"
    end
  end

  test "a new project asks for its first task, not for Done", %{conn: conn, user: user} do
    {:ok, project} = Projects.create_project(user, %{"title" => "Launch"}, command())
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    assert has_element?(view, "#project-empty", "No tasks yet")
    refute has_element?(view, "button", "Mark project done")
    refute has_element?(view, "button", "Drop project")
  end

  test "Done and Drop show once no task is left to do", %{conn: conn, user: user} do
    {:ok, project} = Projects.create_project(user, %{"title" => "Launch"}, command())

    {:ok, task} =
      Tasks.create_task(user, %{"title" => "Ship", "project_id" => project.id}, command())

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    refute has_element?(view, "#project-finished")
    refute has_element?(view, "button", "Mark project done")

    view |> element("#task-#{task.id} button[phx-click=complete]") |> render_click()

    assert has_element?(view, "#project-finished", "Nothing left to do")

    view |> element("#project-finished button", "Mark project done") |> render_click()

    assert Projects.get_project(user, project.id).state == :done
    assert has_element?(view, "#project-resolved", "This project is done")

    view |> element("#project-resolved button", "Reopen") |> render_click()

    assert Projects.get_project(user, project.id).state == :to_do
    refute has_element?(view, "#project-resolved")
  end

  test "Drop project drops it", %{conn: conn, user: user} do
    {:ok, project} = Projects.create_project(user, %{"title" => "Launch"}, command())

    {:ok, task} =
      Tasks.create_task(user, %{"title" => "Ship", "project_id" => project.id}, command())

    {:ok, _} = Tasks.drop_task(user, task.id, command())
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view |> element("#project-finished button", "Drop project") |> render_click()

    assert Projects.get_project(user, project.id).state == :dropped
    assert has_element?(view, "#project-resolved", "This project is dropped")
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
