defmodule MarskalWeb.OpenTasksWindowTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marskal.Tasks
  alias MarskalWeb.OpenTasksLive

  setup %{conn: conn} do
    user = Marskal.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "a short list has no further page", %{conn: conn, user: user} do
    create!(user, %{"title" => "Only one"}, 0)

    {:ok, view, _html} = live(conn, ~p"/open")

    assert has_element?(view, "#open-tasks", "Only one")
    refute has_element?(view, "#open-tasks-more")
  end

  test "open tasks render a window, then the rest", %{conn: conn, user: user} do
    seed_flat!(user)

    {:ok, view, _html} = live(conn, ~p"/open")

    assert has_element?(view, "#open-tasks", newest())
    refute has_element?(view, "#open-tasks", oldest())
    assert has_element?(view, "#open-tasks-more", "Show more")

    view |> element("#open-tasks-more") |> render_click()

    assert has_element?(view, "#open-tasks", oldest())
    refute has_element?(view, "#open-tasks-more")
  end

  test "the next page keeps a parent's subtasks with it", %{conn: conn, user: user} do
    page = OpenTasksLive.row_page()
    create!(user, %{"title" => "Window tail"}, 0)
    parent = create!(user, %{"title" => "Window parent"}, 1)

    for {name, n} <- Enum.with_index(~w(Alpha Bravo Charlie), 2) do
      create!(user, %{"title" => name, "parent_id" => parent.id}, n)
    end

    for n <- 1..(page - 1) do
      create!(user, %{"title" => "Window filler #{n}"}, 10 + n)
    end

    {:ok, view, _html} = live(conn, ~p"/open")

    assert has_element?(view, "#open-tasks li[data-depth='1']", "Alpha")
    assert view |> element("#open-tasks") |> render() =~ ~r/Window parent.*Alpha.*Charlie/s
    refute has_element?(view, "#open-tasks", "Window tail")

    view |> element("#open-tasks-more") |> render_click()

    assert has_element?(view, "#open-tasks", "Window tail")
  end

  test "opening a task keeps the rows already loaded", %{conn: conn, user: user} do
    seed_flat!(user)

    {:ok, view, _html} = live(conn, ~p"/open")
    view |> element("#open-tasks-more") |> render_click()
    view |> element("#open-tasks li.task-row", newest()) |> render_click()

    assert has_element?(view, "#open-tasks li.is-selected", newest())
    assert has_element?(view, "#open-tasks", oldest())
  end

  test "also show starts the window over", %{conn: conn, user: user} do
    seed_flat!(user)

    {:ok, view, _html} = live(conn, ~p"/open")
    view |> element("#open-tasks-more") |> render_click()
    assert has_element?(view, "#open-tasks", oldest())

    view |> element("#visibility-deferred") |> render_click()

    refute has_element?(view, "#open-tasks", oldest())
    assert has_element?(view, "#open-tasks-more")
  end

  defp seed_flat!(user) do
    for n <- 0..OpenTasksLive.row_page(), do: create!(user, %{"title" => title(n)}, n)
  end

  defp title(n), do: "Window #{String.pad_leading(Integer.to_string(n), 3, "0")}"
  defp oldest, do: title(0)
  defp newest, do: title(OpenTasksLive.row_page())

  # The open stream orders by inserted_at. One test transaction shares a
  # timestamp, so each row is pinned to its own second.
  defp create!(user, attrs, n) do
    attrs = Map.put_new(attrs, "inbox", false)
    {:ok, task} = Tasks.create_task(user, attrs, Ecto.UUID.generate(version: 7))

    task
    |> Ecto.Changeset.change(inserted_at: DateTime.add(~U[2020-01-01 00:00:00Z], n, :second))
    |> Marskal.Repo.update!()
  end
end
