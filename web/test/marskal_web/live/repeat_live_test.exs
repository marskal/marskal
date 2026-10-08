defmodule MarskalWeb.RepeatLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  alias Marskal.Recurrence
  alias Marskal.Recurrence.Series
  alias Marskal.Tasks
  alias MarskalWeb.RepeatPanel

  @zone "Europe/Copenhagen"
  @friday ~U[2026-10-09 15:00:00Z]

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "a task starts repeating from the inspector", %{conn: conn, user: user} do
    {:ok, task} =
      Tasks.create_task(user, %{title: "Trash", inbox: false, due_at: @friday}, command())

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#open-tasks li.task-row", "Trash") |> render_click()
    assert has_element?(view, "#inspector-task-repeat", "Does not repeat.")
    refute has_element?(view, "#open-tasks .mark--repeat")

    view |> element("#inspector-task-repeat-open") |> render_click()

    view
    |> form("#inspector-task-repeat-form",
      repeat: %{interval: "2", frequency: "weeks", mode: "regular", anchor: "due", ends: "never"}
    )
    |> render_change(%{"repeat" => %{"weekdays" => ["", "2", "5"]}})

    assert has_element?(view, "#inspector-task-repeat-form input[value='5'][checked]")
    assert Tasks.get_task(user, task.id).series_id == nil

    view |> form("#inspector-task-repeat-form") |> render_submit()

    %{series_id: series_id, occurrence_for: @friday} = Tasks.get_task(user, task.id)

    assert %Series{interval: 2, frequency: :weeks, weekdays: [2, 5], mode: :regular} =
             Recurrence.get_series(user, series_id)

    assert has_element?(
             view,
             "#inspector-task-repeat-summary",
             "Every 2 weeks on Tue and Fri, on schedule."
           )

    assert has_element?(view, "#open-tasks .mark--repeat")
  end

  test "it needs the date the rule moves", %{conn: conn, user: user} do
    {:ok, task} = Tasks.create_task(user, %{title: "Water plants", inbox: false}, command())

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#open-tasks li.task-row", "Water plants") |> render_click()
    view |> element("#inspector-task-repeat-open") |> render_click()

    view
    |> form("#inspector-task-repeat-form",
      repeat: %{interval: "3", frequency: "days", mode: "on_completion", anchor: "planned"}
    )
    |> render_submit()

    assert render(view) =~ "The date it moves needs the task&#39;s Planned date."
    assert has_element?(view, "#inspector-task-repeat-interval[value='3']")
    assert Tasks.get_task(user, task.id).series_id == nil
  end

  test "a running rule saves each change, and stops and resumes", %{conn: conn, user: user} do
    {:ok, task} =
      Tasks.create_task(user, %{title: "Trash", inbox: false, due_at: @friday}, command())

    rule = %{mode: :regular, anchor: :due, interval: 1, frequency: :weeks}
    {:ok, series} = Recurrence.repeat_task(user, task.id, rule, command())

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#open-tasks li.task-row", "Trash") |> render_click()

    # Months and a count bring their own fields.
    view
    |> form("#inspector-task-repeat-form", repeat: %{frequency: "months", ends: "count"})
    |> render_change()

    view
    |> form("#inspector-task-repeat-form",
      repeat: %{month_ordinal: "-1", month_day_kind: "work_day", end_count: "6"}
    )
    |> render_change()

    assert %Series{frequency: :months, month_ordinal: -1, month_day_kind: :work_day, end_count: 6} =
             Recurrence.get_series(user, series.id)

    assert has_element?(
             view,
             "#inspector-task-repeat-summary",
             "Every month on the last work day, on schedule. Moves the Due date. Ends after 6."
           )

    view |> element("#inspector-task-repeat-stop") |> render_click()
    assert Recurrence.get_series(user, series.id).stopped_at
    assert has_element?(view, "#inspector-task-repeat", "Stopped.")
    refute has_element?(view, "#open-tasks .mark--repeat")

    view |> element("#inspector-task-repeat-resume") |> render_click()
    assert Recurrence.get_series(user, series.id).stopped_at == nil
    assert has_element?(view, "#inspector-task-repeat-form")
  end

  describe "params_to_attrs/2" do
    test "clears day limits the frequency or mode does not take" do
      base = %{"interval" => "1", "anchor" => "due", "weekdays" => ["", "1"]}

      assert %{"weekdays" => ["1"]} =
               RepeatPanel.params_to_attrs(
                 Map.merge(base, %{"mode" => "regular", "frequency" => "weeks"}),
                 @zone
               )

      assert %{"weekdays" => [], "month_ordinal" => nil, "month_day_kind" => nil} =
               RepeatPanel.params_to_attrs(
                 Map.merge(base, %{
                   "mode" => "on_completion",
                   "frequency" => "weeks",
                   "month_ordinal" => "1",
                   "month_day_kind" => "monday"
                 }),
                 @zone
               )
    end

    test "an end day is inclusive, to its last second on the zone's clock" do
      assert %{"ends_at" => ends_at, "end_count" => nil} =
               RepeatPanel.params_to_attrs(
                 %{
                   "mode" => "regular",
                   "frequency" => "days",
                   "ends" => "date",
                   "ends_on" => "2026-12-31"
                 },
                 @zone
               )

      assert ends_at == ~U[2026-12-31 22:59:59Z]
    end
  end

  describe "describe/2" do
    test "reads the rule" do
      rule = %Series{
        mode: :on_completion,
        anchor: :defer,
        interval: 3,
        frequency: :days,
        weekdays: [],
        month_days: [],
        week_start: 1
      }

      assert RepeatPanel.describe(rule, @zone) ==
               "Every 3 days, after finishing the last one. Moves the Defer date."

      assert RepeatPanel.describe(
               %{rule | mode: :regular, interval: 1, frequency: :months, month_days: [-1, 1, 15]},
               @zone
             ) ==
               "Every month on the 1st, the 15th and the last day, on schedule. Moves the Defer date."

      assert RepeatPanel.describe(
               %{rule | mode: :regular, frequency: :weeks, weekdays: [1, 7], week_start: 7},
               @zone
             ) =~ "on Sun and Mon"
    end
  end

  defp command, do: Ecto.UUID.generate()
end
