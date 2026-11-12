defmodule MarskalWeb.ReviewLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  alias Marskal.Accounts
  alias Marskal.Dates
  alias Marskal.Projects
  alias Marskal.Tasks
  alias MarskalWeb.ReviewIntervals

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user, today: Dates.today("Europe/Copenhagen")}
  end

  describe "the Review view" do
    test "lists the projects due, and the sidebar counts them", %{
      conn: conn,
      user: user,
      today: today
    } do
      stalled = due!(user, "Garden", today)
      paused = due!(user, "Taxes", today, %{deferred_indefinitely: true})
      _later = due!(user, "Later", Date.add(today, 2))
      {:ok, _} = Tasks.create_task(user, %{title: "Milk"}, command())

      {:ok, view, _html} = live(conn, ~p"/review")

      assert has_element?(view, "#review-#{stalled.id}", "Stalled")
      assert has_element?(view, "#review-#{paused.id}", "Deferred")
      refute has_element?(view, "#review-#{paused.id}", "Stalled")
      refute has_element?(view, "#review-projects", "Later")
      assert has_element?(view, "#review-inbox", "1 item in the Inbox")
      assert has_element?(view, "#sidebar-review-count", "2")

      view |> element("#review-#{stalled.id}-done") |> render_click()

      refute has_element?(view, "#review-#{stalled.id}")
      assert has_element?(view, "#sidebar-review-count", "1")
    end

    test "says so when nothing is due", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/review")
      assert has_element?(view, "#review-empty")
      refute has_element?(view, "#sidebar-review-count")
    end

    test "Mark reviewed on the project moves on to the next, then back", %{
      conn: conn,
      user: user,
      today: today
    } do
      first = due!(user, "First", Date.add(today, -1))
      second = due!(user, "Second", today)

      {:ok, view, _html} = live(conn, ~p"/projects/#{first.id}?review=1")
      assert has_element?(view, "#project-review", "Due for review")

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> element("#project-reviewed") |> render_click()

      assert to == ~p"/projects/#{second.id}?review=1"

      {:ok, view, _html} = live(conn, to)

      assert {:error, {:live_redirect, %{to: "/review"}}} =
               view |> element("#project-reviewed") |> render_click()

      {:ok, view, _html} = live(conn, ~p"/projects/#{first.id}?review=1")
      assert has_element?(view, "#project-review", "Next review")
      refute has_element?(view, "#project-reviewed")

      {:ok, view, _html} = live(conn, ~p"/projects/#{first.id}")
      refute has_element?(view, "#project-review")
    end

    test "is a view Go to finds", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/open")
      assert render(view) =~ ~s(href="/review")
    end
  end

  describe "the inspector" do
    test "picks a preset, and Custom saves once it reads", %{conn: conn, user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}?project=#{project.id}")

      assert has_element?(
               view,
               "#inspector-project-review-picker-choice option[selected]",
               "Every week"
             )

      pick(view, %{"interval" => "P1M"})
      assert Projects.get_project(user, project.id).review_interval == Duration.new!(month: 1)

      pick(view, %{"interval" => "custom", "interval_custom" => ""})
      assert has_element?(view, "#inspector-project-review-picker-custom")

      pick(view, %{"interval" => "custom", "interval_custom" => "pt1h"})
      assert has_element?(view, "#inspector-project-review-picker-words", "whole days")
      assert Projects.get_project(user, project.id).review_interval == Duration.new!(month: 1)

      pick(view, %{"interval" => "custom", "interval_custom" => "p2w3d"})
      assert has_element?(view, "#inspector-project-review-picker-words", "Every 17 days")
      assert Projects.get_project(user, project.id).review_interval == Duration.new!(day: 17)

      pick(view, %{"interval" => "never"})
      assert Projects.get_project(user, project.id).next_review_on == nil
      refute has_element?(view, "#inspector-project-review-done")
    end

    test "types the next review day, and marks it reviewed", %{
      conn: conn,
      user: user,
      today: today
    } do
      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}?project=#{project.id}")

      assert has_element?(view, "#inspector-project-review-last", "Not reviewed yet")

      day = Date.add(today, 30)

      view
      |> form("#inspector-project-review-next", %{"next" => Date.to_iso8601(day)})
      |> render_submit()

      assert Projects.get_project(user, project.id).next_review_on == day

      view |> element("#inspector-project-review-done") |> render_click()

      reviewed = Projects.get_project(user, project.id)
      assert reviewed.next_review_on == Date.add(today, 7)
      assert has_element?(view, "#inspector-project-review-last", "Last reviewed")
    end
  end

  test "settings set the interval new projects take", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/users/settings")

    view
    |> form("#preferences_form", %{"preferences" => %{"default_review_interval" => "P3M"}})
    |> render_change()

    assert Accounts.preferences(user).default_review_interval == Duration.new!(month: 3)

    view
    |> form("#preferences_form", %{"preferences" => %{"default_review_interval" => "custom"}})
    |> render_change()

    assert has_element?(view, "#preferences-review-interval-custom")
    assert Accounts.preferences(user).default_review_interval == Duration.new!(month: 3)

    view
    |> form("#preferences_form", %{
      "preferences" => %{
        "default_review_interval" => "custom",
        "default_review_interval_custom" => "P1Y6M"
      }
    })
    |> render_change()

    assert Accounts.preferences(user).default_review_interval == Duration.new!(year: 1, month: 6)

    view
    |> form("#preferences_form", %{"preferences" => %{"default_review_interval" => "never"}})
    |> render_change()

    assert Accounts.preferences(user).default_review_interval == nil
  end

  test "the help page explains the format", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/help/review-intervals")
    assert has_element?(view, "#help-review-intervals td", "Every 1 month, 15 days")
  end

  test "intervals in words" do
    assert ReviewIntervals.words(nil) == "Never"
    assert ReviewIntervals.words(Duration.new!(day: 7)) == "Every week"
    assert ReviewIntervals.words(Duration.new!(day: 14)) == "Every 2 weeks"
    assert ReviewIntervals.words(Duration.new!(day: 10)) == "Every 10 days"
    assert ReviewIntervals.words(Duration.new!(month: 1)) == "Every month"
    assert ReviewIntervals.words(Duration.new!(year: 2)) == "Every 2 years"
    assert ReviewIntervals.words(Duration.new!(month: 1, day: 15)) == "Every 1 month, 15 days"
    assert ReviewIntervals.choice(Duration.new!(day: 14)) == "P14D"
    assert ReviewIntervals.choice(Duration.new!(day: 17)) == "custom"
    assert ReviewIntervals.choice(nil) == "never"
  end

  defp pick(view, params) do
    view |> form("#inspector-project-review-interval") |> render_change(params)
  end

  defp due!(user, title, day, attrs \\ %{}) do
    {:ok, project} = Projects.create_project(user, Map.put(attrs, :title, title), command())
    {:ok, project} = Projects.update_project(user, project.id, %{next_review_on: day}, command())
    project
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
