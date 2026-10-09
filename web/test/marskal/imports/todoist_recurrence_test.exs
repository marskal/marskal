defmodule Marskal.Imports.TodoistRecurrenceTest do
  use ExUnit.Case, async: true

  alias Marskal.Imports.TodoistRecurrence

  defp rule(text), do: TodoistRecurrence.parse(text)

  defp ok(frequency, attrs \\ %{}) do
    {:ok,
     Map.merge(
       %{
         "mode" => "regular",
         "anchor" => "planned",
         "interval" => 1,
         "frequency" => frequency,
         "weekdays" => [],
         "on_days" => []
       },
       attrs
     )}
  end

  test "an interval, alone or as every so many" do
    assert rule("daily") == ok("days")
    assert rule("Every day") == ok("days")
    assert rule("every 3 weeks") == ok("weeks", %{"interval" => 3})
    assert rule("every other month") == ok("months", %{"interval" => 2})
    assert rule("annually") == ok("years")
    assert rule("every 2 hours") == ok("hours", %{"interval" => 2})
  end

  test "weekdays" do
    assert rule("every mon, fri") == ok("weeks", %{"weekdays" => [1, 5]})
    assert rule("every monday and thursday") == ok("weeks", %{"weekdays" => [1, 4]})
    assert rule("every other tuesday") == ok("weeks", %{"interval" => 2, "weekdays" => [2]})
    assert rule("every weekday") == ok("weeks", %{"weekdays" => [1, 2, 3, 4, 5]})
    assert rule("every weekend") == ok("weeks", %{"weekdays" => [6, 7]})

    assert rule("every 2 weeks on mon and thu") ==
             ok("weeks", %{"interval" => 2, "weekdays" => [1, 4]})
  end

  test "days of the month" do
    assert rule("every 15th") == ok("months", %{"on_days" => ["15:day"]})
    assert rule("every 1st and 15th") == ok("months", %{"on_days" => ["1:day", "15:day"]})
    assert rule("every last day") == ok("months", %{"on_days" => ["-1:day"]})
    assert rule("every 2nd tuesday") == ok("months", %{"on_days" => ["2:tuesday"]})
    assert rule("every last workday") == ok("months", %{"on_days" => ["-1:work_day"]})
    assert rule("every first work day") == ok("months", %{"on_days" => ["1:work_day"]})
    assert rule("every month on the 15th") == ok("months", %{"on_days" => ["15:day"]})

    assert rule("every 15th and last day") ==
             ok("months", %{"on_days" => ["15:day", "-1:day"]})
  end

  test "days of the year" do
    assert rule("every jan 15") == ok("years", %{"on_days" => ["1:15:day"]})
    assert rule("every 15 january") == ok("years", %{"on_days" => ["1:15:day"]})
    assert rule("every year on mar 1st") == ok("years", %{"on_days" => ["3:1:day"]})
  end

  test "every! repeats after completion, without days" do
    assert rule("every! 3 days") == ok("days", %{"mode" => "on_completion", "interval" => 3})
    assert rule("every! week") == ok("weeks", %{"mode" => "on_completion"})
    assert rule("every! monday") == :error
  end

  test "a trailing time is dropped" do
    assert rule("every day at 9am") == ok("days")
    assert rule("every mon at 17:00") == ok("weeks", %{"weekdays" => [1]})
  end

  test "free-form text is not read" do
    for text <- [
          "every other tuesday starting next month",
          "every 3rd workday until june",
          "every day for 5 times",
          "every mon and 15th",
          "every 3 mondays",
          "every week on the 15th",
          "after 3 days",
          "",
          nil
        ] do
      assert rule(text) == :error, inspect(text)
    end
  end
end
