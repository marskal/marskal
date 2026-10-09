defmodule MarskalWeb.RepeatLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  alias Marskal.Dates
  alias Marskal.Recurrence
  alias Marskal.Recurrence.Series
  alias Marskal.Tasks
  alias MarskalWeb.RepeatPanel

  @zone "Europe/Copenhagen"
  # Friday 9 October, 17:00 in Copenhagen.
  @friday ~U[2026-10-09 15:00:00Z]
  @dialog "#inspector-task-repeat-dialog"

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "a weekly rule starts on the task's weekday, and takes more days", %{
    conn: conn,
    user: user
  } do
    task = task_fixture(user, %{due_at: @friday})
    view = inspect_task(conn, "Trash")
    refute has_element?(view, "#open-tasks .mark--repeat")

    view |> element("#inspector-task-repeat-open") |> render_click()
    assert has_element?(view, "#{@dialog}-repeat option[value='weekly'][selected]")
    assert has_element?(view, "#{@dialog}-weekday-0 option[value='5'][selected]")

    view |> element("#{@dialog}-add-0") |> render_click()
    assert has_element?(view, "#{@dialog}-weekday-1 option[value='6'][selected]")

    view |> form("#{@dialog}-form", repeat: %{weekdays: %{"1" => "2"}}) |> render_change()
    view |> form("#{@dialog}-form") |> render_submit()

    refute has_element?(view, @dialog)
    %{series_id: series_id, occurrence_for: @friday} = Tasks.get_task(user, task.id)

    assert %Series{mode: :regular, frequency: :weeks, weekdays: [2, 5]} =
             Recurrence.get_series(user, series_id)

    assert has_element?(view, "#inspector-task-repeat-summary", "Repeats weekly on Tue and Fri")
    assert has_element?(view, "#open-tasks .mark--repeat")
  end

  test "monthly rows are days and nth weekdays, and a row comes off", %{
    conn: conn,
    user: user
  } do
    task = task_fixture(user, %{due_at: @friday})
    view = inspect_task(conn, "Trash")
    view |> element("#inspector-task-repeat-open") |> render_click()

    view |> form("#{@dialog}-form", repeat: %{repeat: "monthly"}) |> render_change()
    assert has_element?(view, "#{@dialog}-ordinal-0 option[value='9'][selected]")

    view |> element("#{@dialog}-add-0") |> render_click()
    view |> element("#{@dialog}-add-1") |> render_click()
    view |> element("#{@dialog}-remove-2") |> render_click()
    refute has_element?(view, "#{@dialog}-ordinal-2")

    view
    |> form("#{@dialog}-form",
      repeat: %{rows: %{"1" => %{ordinal: "-1", kind: "work_day"}}, ends: "count"}
    )
    |> render_change()

    view |> form("#{@dialog}-form", repeat: %{end_count: "6"}) |> render_submit()

    assert %Series{frequency: :months, on_days: ["9:day", "-1:work_day"], end_count: 6} =
             Recurrence.get_series(user, Tasks.get_task(user, task.id).series_id)

    assert has_element?(
             view,
             "#inspector-task-repeat-summary",
             "Repeats monthly on the 9th and the last work day, 6 repetitions"
           )
  end

  test "a row may count from the end", %{conn: conn, user: user} do
    task = task_fixture(user, %{due_at: @friday})
    view = inspect_task(conn, "Trash")
    view |> element("#inspector-task-repeat-open") |> render_click()
    view |> form("#{@dialog}-form", repeat: %{repeat: "monthly"}) |> render_change()

    view
    |> form("#{@dialog}-form", repeat: %{rows: %{"0" => %{ordinal: "-2", kind: "friday"}}})
    |> render_change()

    view
    |> form("#{@dialog}-form", repeat: %{rows: %{"0" => %{ordinal: "1", kind: "work_day"}}})
    |> render_change()

    assert has_element?(view, "#{@dialog}-ordinal-0 option[value='23']", "23rd")

    view
    |> form("#{@dialog}-form", repeat: %{rows: %{"0" => %{ordinal: "-2", kind: "friday"}}})
    |> render_change()

    refute has_element?(view, "#{@dialog}-ordinal-0 option[value='6']")
    assert has_element?(view, "#{@dialog}-ordinal-0 option[value='-2'][selected]", "2nd to last")
    view |> form("#{@dialog}-form") |> render_submit()

    assert %Series{on_days: ["-2:friday"]} =
             Recurrence.get_series(user, Tasks.get_task(user, task.id).series_id)

    assert has_element?(
             view,
             "#inspector-task-repeat-summary",
             "Repeats monthly on the 2nd to last Friday"
           )
  end

  test "a yearly row names its month", %{conn: conn, user: user} do
    task = task_fixture(user, %{due_at: @friday})
    view = inspect_task(conn, "Trash")
    view |> element("#inspector-task-repeat-open") |> render_click()

    view |> form("#{@dialog}-form", repeat: %{repeat: "yearly"}) |> render_change()
    assert has_element?(view, "#{@dialog}-month-0 option[value='10'][selected]")

    view |> element("#{@dialog}-add-0") |> render_click()

    view
    |> form("#{@dialog}-form",
      repeat: %{rows: %{"1" => %{ordinal: "-1", kind: "monday", month: "4"}}}
    )
    |> render_change()

    view |> form("#{@dialog}-form") |> render_submit()

    assert %Series{frequency: :years, on_days: ["4:-1:monday", "10:9:day"]} =
             Recurrence.get_series(user, Tasks.get_task(user, task.id).series_id)

    assert has_element?(
             view,
             "#inspector-task-repeat-summary",
             "Repeats yearly on the last Monday in Apr and 9 Oct"
           )
  end

  test "Next sets the date the rule moves, and the dialog shows the dates after it", %{
    conn: conn,
    user: user
  } do
    task = task_fixture(user, %{})
    view = inspect_task(conn, "Trash")
    view |> element("#inspector-task-repeat-open") |> render_click()

    view
    |> form("#{@dialog}-form", repeat: %{repeat: "daily", next: "2026-11-02", anchor: "planned"})
    |> render_change()

    assert has_element?(view, "#{@dialog}-next", "3 Nov, 4 Nov, 5 Nov, …")

    view |> form("#{@dialog}-form") |> render_submit()

    planned = Dates.from_local(~D[2026-11-02], nil, :planned_at, @zone)
    assert %{planned_at: ^planned, occurrence_for: ^planned} = Tasks.get_task(user, task.id)
  end

  test "after completion is an interval and a unit", %{conn: conn, user: user} do
    task = task_fixture(user, %{due_at: @friday})
    view = inspect_task(conn, "Trash")
    view |> element("#inspector-task-repeat-open") |> render_click()

    view |> form("#{@dialog}-form", repeat: %{repeat: "after"}) |> render_change()

    view
    |> form("#{@dialog}-form", repeat: %{interval: "3", unit: "days"})
    |> render_submit()

    assert %Series{mode: :on_completion, frequency: :days, interval: 3, weekdays: [], on_days: []} =
             Recurrence.get_series(user, Tasks.get_task(user, task.id).series_id)

    assert has_element?(view, "#inspector-task-repeat-summary", "Repeats 3 days after completion")
  end

  test "Cancel leaves the task as it was", %{conn: conn, user: user} do
    task = task_fixture(user, %{due_at: @friday})
    view = inspect_task(conn, "Trash")
    view |> element("#inspector-task-repeat-open") |> render_click()
    view |> form("#{@dialog}-form", repeat: %{repeat: "monthly"}) |> render_change()

    view |> element("#{@dialog}-cancel") |> render_click()

    refute has_element?(view, @dialog)
    assert Tasks.get_task(user, task.id).series_id == nil

    view |> element("#inspector-task-repeat-open") |> render_click()
    assert has_element?(view, "#{@dialog}-repeat option[value='weekly'][selected]")
  end

  test "a missing anchor date is said in the dialog", %{conn: conn, user: user} do
    task = task_fixture(user, %{due_at: @friday})
    view = inspect_task(conn, "Trash")
    view |> element("#inspector-task-repeat-open") |> render_click()

    view |> form("#{@dialog}-form", repeat: %{interval: "0"}) |> render_submit()

    assert has_element?(view, "#{@dialog} .errors", "Every must be greater than 0.")
    assert Tasks.get_task(user, task.id).series_id == nil
  end

  test "the line's menu edits, pauses, resumes, shows the previous copy, and stops", %{
    conn: conn,
    user: user
  } do
    task = task_fixture(user, %{due_at: @friday})
    rule = %{mode: :regular, anchor: :due, interval: 1, frequency: :days}
    {:ok, series} = Recurrence.repeat_task(user, task.id, rule, command())
    {:ok, _} = Tasks.complete_task(user, task.id, command())
    [next] = Enum.reject(Tasks.list_open(user), &(&1.id == task.id))

    {:ok, view, _html} = live(conn, ~p"/?task=#{next.id}")
    assert has_element?(view, "#inspector-task-repeat-summary", "Repeats daily")

    view |> element("#inspector-task-repeat-edit") |> render_click()
    assert has_element?(view, "#{@dialog}-repeat option[value='daily'][selected]")
    view |> form("#{@dialog}-form", repeat: %{interval: "2"}) |> render_submit()
    assert Recurrence.get_series(user, series.id).interval == 2

    view |> element("#inspector-task-repeat-pause") |> render_click()
    assert Recurrence.get_series(user, series.id).stopped_at
    assert has_element?(view, "#inspector-task-repeat-line", "Paused")

    view |> element("#inspector-task-repeat-resume") |> render_click()
    assert Recurrence.get_series(user, series.id).stopped_at == nil

    view |> element("#inspector-task-repeat-previous") |> render_click()
    assert_patch(view, ~p"/?task=#{task.id}")

    view |> element("#inspector-task-repeat-stop") |> render_click()
    assert Recurrence.get_series(user, series.id) == nil
    assert has_element?(view, "#inspector-task-repeat", "Its series was deleted")
  end

  describe "draft_to_attrs/2" do
    test "clears the days a kind of repeat does not take" do
      draft = %{
        repeat: :daily,
        interval: 1,
        unit: :weeks,
        anchor: :due,
        next: ~D[2026-10-09],
        ends: :date,
        ends_on: ~D[2026-12-31],
        end_count: nil,
        weekdays: [5],
        rows: [{nil, 9, :day}]
      }

      assert %{"frequency" => "days", "weekdays" => [], "on_days" => [], "ends_at" => ends_at} =
               RepeatPanel.draft_to_attrs(draft, @zone)

      # The end day counts to its last second on the zone's clock.
      assert ends_at == ~U[2026-12-31 22:59:59Z]

      assert %{"mode" => "on_completion", "frequency" => "months", "ends_at" => nil} =
               RepeatPanel.draft_to_attrs(%{draft | repeat: :after, unit: :months}, @zone)
    end
  end

  defp task_fixture(user, attrs) do
    {:ok, task} =
      Tasks.create_task(user, Map.merge(%{title: "Trash", inbox: false}, attrs), command())

    task
  end

  defp inspect_task(conn, title) do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#open-tasks li.task-row", title) |> render_click()
    view
  end

  defp command, do: Ecto.UUID.generate()
end
