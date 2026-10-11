defmodule MarskalWeb.TaskControllerTest do
  use MarskalWeb.ConnCase, async: true

  import Marskal.AccountsFixtures

  alias Marskal.Projects
  alias Marskal.Tasks

  setup :register_and_log_in_user

  defp command, do: Ecto.UUID.generate(version: 7)

  test "a task link opens the inspector on it where it lives", %{conn: conn, user: user} do
    {:ok, project} = Projects.create_project(user, %{"title" => "Home"}, command())

    {:ok, in_project} =
      Tasks.create_task(user, %{"title" => "Paint", "project_id" => project.id}, command())

    {:ok, in_inbox} = Tasks.create_task(user, %{"title" => "Call"}, command())
    {:ok, no_project} = Tasks.create_task(user, %{"title" => "Milk", "inbox" => false}, command())

    assert redirected_to(get(conn, ~p"/tasks/#{in_project.id}")) ==
             ~p"/projects/#{project.id}?task=#{in_project.id}"

    assert redirected_to(get(conn, ~p"/tasks/#{in_inbox.id}")) == ~p"/inbox?task=#{in_inbox.id}"
    assert redirected_to(get(conn, ~p"/tasks/#{no_project.id}")) == ~p"/?task=#{no_project.id}"
  end

  test "another user's task or a malformed id is not available", %{conn: conn} do
    {:ok, task} = Tasks.create_task(user_fixture(), %{"title" => "Secret"}, command())

    for id <- [task.id, "not-a-uuid"] do
      conn = get(conn, ~p"/tasks/#{id}")
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "That task is not available."
    end
  end
end
