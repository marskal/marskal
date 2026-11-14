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

      refute has_element?(view, "#review-#{stalled.id}-done")
      assert has_element?(view, "#review-#{stalled.id}-open")

      # Start review opens the first due project, to be looked over there.
      view |> element("#review-start") |> render_click()
      assert_redirect(view, ~p"/projects/#{stalled.id}?review=1")
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
    test "picks a number and a unit, or Never", %{conn: conn, user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}?project=#{project.id}")

      assert has_element?(view, "#inspector-project-review-picker-count[value='1']")
      assert has_element?(view, "#inspector-project-review-picker-unit option[selected]", "week")

      pick(view, %{"interval" => "month", "interval_count" => "3"})
      assert Projects.get_project(user, project.id).review_interval == Duration.new!(month: 3)

      assert has_element?(
               view,
               "#inspector-project-review-picker-unit option[selected]",
               "months"
             )

      pick(view, %{"interval" => "month", "interval_count" => ""})
      assert has_element?(view, "#inspector-project-review-picker-count[value='']")
      assert Projects.get_project(user, project.id).review_interval == Duration.new!(month: 3)

      pick(view, %{"interval" => "month", "interval_count" => "1.5"})
      assert has_element?(view, "#inspector-project-review-picker-error", "whole number")
      assert Projects.get_project(user, project.id).review_interval == Duration.new!(month: 3)

      # Typed days stay days, though they are whole weeks.
      pick(view, %{"interval" => "day", "interval_count" => "14"})
      assert Projects.get_project(user, project.id).review_interval == Duration.new!(day: 14)
      assert has_element?(view, "#inspector-project-review-picker-unit option[selected]", "days")

      pick(view, %{"interval" => "never"})
      assert Projects.get_project(user, project.id).next_review_on == nil
      refute has_element?(view, "#inspector-project-review-picker-count")
      refute has_element?(view, "#inspector-project-review-done")

      # From Never, a unit alone counts one.
      pick(view, %{"interval" => "year"})
      assert Projects.get_project(user, project.id).review_interval == Duration.new!(year: 1)
    end

    test "keeps a mixed interval until another is picked", %{conn: conn, user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())
      mixed = Duration.new!(month: 1, day: 15)
      {:ok, _} = Projects.update_project(user, project.id, %{review_interval: mixed}, command())
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}?project=#{project.id}")

      assert has_element?(
               view,
               "#inspector-project-review-picker-unit option[selected]",
               "Every 1 month, 15 days"
             )

      refute has_element?(view, "#inspector-project-review-picker-count")
      pick(view, %{"interval" => "keep"})
      assert Projects.get_project(user, project.id).review_interval == mixed

      pick(view, %{"interval" => "week"})
      assert Projects.get_project(user, project.id).review_interval == Duration.new!(day: 7)
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
    |> form("#preferences_form", %{
      "preferences" => %{
        "default_review_interval" => "month",
        "default_review_interval_count" => "18"
      }
    })
    |> render_change()

    assert Accounts.preferences(user).default_review_interval == Duration.new!(year: 1, month: 6)

    view
    |> form("#preferences_form", %{
      "preferences" => %{
        "default_review_interval" => "month",
        "default_review_interval_count" => ""
      }
    })
    |> render_change()

    assert has_element?(view, "#preferences-review-interval-count[value='']")
    assert Accounts.preferences(user).default_review_interval == Duration.new!(year: 1, month: 6)

    view
    |> form("#preferences_form", %{"preferences" => %{"default_review_interval" => "never"}})
    |> render_change()

    assert Accounts.preferences(user).default_review_interval == nil
  end

  test "intervals in words" do
    assert ReviewIntervals.words(nil) == "Never"
    assert ReviewIntervals.words(Duration.new!(day: 7)) == "Every week"
    assert ReviewIntervals.words(Duration.new!(day: 14)) == "Every 2 weeks"
    assert ReviewIntervals.words(Duration.new!(day: 10)) == "Every 10 days"
    assert ReviewIntervals.words(Duration.new!(month: 1)) == "Every month"
    assert ReviewIntervals.words(Duration.new!(year: 2)) == "Every 2 years"
    assert ReviewIntervals.words(Duration.new!(month: 1, day: 15)) == "Every 1 month, 15 days"
  end

  test "an interval as a number and a unit" do
    assert ReviewIntervals.split(nil) == {nil, "never"}
    assert ReviewIntervals.split(Duration.new!(day: 14)) == {2, "week"}
    assert ReviewIntervals.split(Duration.new!(day: 17)) == {17, "day"}
    assert ReviewIntervals.split(Duration.new!(year: 1, month: 6)) == {18, "month"}
    assert ReviewIntervals.split(Duration.new!(year: 2)) == {2, "year"}
    assert ReviewIntervals.split(Duration.new!(month: 1, day: 15)) == {nil, "keep"}

    assert ReviewIntervals.read("week", "3") == {:ok, Duration.new!(day: 21)}
    assert ReviewIntervals.read("month", "12") == {:ok, Duration.new!(year: 1)}
    assert ReviewIntervals.read("day", nil) == {:ok, Duration.new!(day: 1)}
    assert ReviewIntervals.read("day", " ") == :pending
    assert {:error, _} = ReviewIntervals.read("day", "0")
    assert {:error, _} = ReviewIntervals.read("day", "1000")
    assert {:error, _} = ReviewIntervals.read("hour", "1")
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
