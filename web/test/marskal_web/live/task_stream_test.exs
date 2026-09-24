defmodule MarskalWeb.TaskStreamTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "capture, clarify, complete, and drop", %{conn: conn} do
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

    {:ok, inbox, _html} = live(conn, ~p"/inbox")

    inbox
    |> form("#new-task", task: %{title: "Bread"})
    |> render_submit()

    inbox
    |> element("#inbox-tasks button", "Drop")
    |> render_click()

    refute has_element?(inbox, "#inbox-tasks", "Bread")
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
end
