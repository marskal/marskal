defmodule MarskalWeb.TaskStreamTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "capture, clarify, and complete", %{conn: conn} do
    {:ok, inbox, _html} = live(conn, ~p"/inbox")

    inbox
    |> form("#new-task", task: %{title: "Milk"})
    |> render_submit()

    assert has_element?(inbox, "#inbox-tasks", "Milk")

    inbox
    |> element("#inbox-tasks button", "Clarify")
    |> render_click()

    refute has_element?(inbox, "#inbox-tasks", "Milk")

    {:ok, open, _html} = live(conn, ~p"/")
    assert has_element?(open, "#open-tasks", "Milk")

    open
    |> element("#open-tasks button[aria-label='Mark as done']")
    |> render_click()

    refute has_element?(open, "#open-tasks", "Milk")
  end

  test "tasks on an on-hold tag hide until unavailable ones are shown", %{conn: conn, user: user} do
    {:ok, task} =
      Marskal.Tasks.create_task(user, %{"title" => "Ask Anna", "inbox" => false}, command())

    {:ok, tag} = Marskal.Tags.create_tag(user, %{"name" => "Waiting"}, command())
    {:ok, _} = Marskal.Tags.tag_task(user, task.id, tag.id, command())
    {:ok, _} = Marskal.Tags.set_tag_state(user, tag.id, :on_hold, command())

    {:ok, open, _html} = live(conn, ~p"/")
    refute has_element?(open, "#open-tasks", "Ask Anna")

    open |> element("a", "Show unavailable") |> render_click()
    assert_patch(open, ~p"/?unavailable=1")
    assert has_element?(open, "#open-tasks", "Ask Anna")

    open |> element("a", "Hide unavailable") |> render_click()
    refute has_element?(open, "#open-tasks", "Ask Anna")
  end

  test "another user does not see the task", %{conn: conn} do
    {:ok, inbox, _html} = live(conn, ~p"/inbox")

    inbox
    |> form("#new-task", task: %{title: "Secret"})
    |> render_submit()

    other = log_in_user(build_conn(), user_fixture())
    {:ok, _inbox, html} = live(other, ~p"/inbox")
    refute html =~ "Secret"
  end

  defp command, do: Ecto.UUID.generate()
end
