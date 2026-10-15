defmodule Marskal.Imports.OmnifocusRecurrenceTest do
  use ExUnit.Case, async: true

  alias Marskal.Imports.OmnifocusRecurrence
  alias Marskal.Recurrence.Series

  @due "2026-10-09T15:00:00.000Z"

  defp read(rule, row \\ %{}) do
    %{
      "repeat" => rule,
      "due" => @due,
      "repeat_schedule" => "regularly",
      "repeat_anchor" => "due-date"
    }
    |> Map.merge(row)
    |> OmnifocusRecurrence.read()
  end

  describe "exact" do
    test "an interval, with the anchor and mode OmniFocus names" do
      assert {:ok, rule, []} = read("FREQ=DAILY;INTERVAL=3")

      assert %{"mode" => "regular", "anchor" => "due", "frequency" => "days", "interval" => 3} =
               rule

      assert Series.valid_rule?(rule)

      for {freq, unit} <- [{"MINUTELY", "minutes"}, {"HOURLY", "hours"}, {"YEARLY", "years"}] do
        assert {:ok, %{"frequency" => ^unit, "interval" => 1}, []} = read("FREQ=#{freq}")
      end
    end

    test "weekdays, and the week start" do
      assert {:ok, %{"weekdays" => [2, 4], "week_start" => 7} = rule, []} =
               read("FREQ=WEEKLY;INTERVAL=2;BYDAY=TH,TU;WKST=SU")

      assert Series.valid_rule?(rule)
    end

    test "days of the month and nth weekdays" do
      assert {:ok, %{"on_days" => ["15:day", "-1:day"]}, []} =
               read("FREQ=MONTHLY;BYMONTHDAY=15,-1")

      assert {:ok, %{"on_days" => ["2:tuesday", "-1:friday"]} = rule, []} =
               read("FREQ=MONTHLY;BYDAY=2TU,-1FR")

      assert Series.valid_rule?(rule)
    end

    test "work and weekend days by position" do
      assert {:ok, %{"on_days" => ["-1:work_day"]}, []} =
               read("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1")

      assert {:ok, %{"on_days" => ["1:weekend_day"]}, []} =
               read("FREQ=MONTHLY;BYDAY=SA,SU;BYSETPOS=1")

      assert {:ok, %{"on_days" => ["3:monday"]}, []} = read("FREQ=MONTHLY;BYDAY=MO;BYSETPOS=3")
    end

    test "a yearly rule names its months" do
      assert {:ok, %{"on_days" => ["4:14:day", "10:14:day"]} = rule, []} =
               read("FREQ=YEARLY;BYMONTH=4,10;BYMONTHDAY=14")

      assert Series.valid_rule?(rule)

      assert {:ok, %{"on_days" => ["11:4:thursday"]}, []} =
               read("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH")
    end

    test "an end by count or date" do
      assert {:ok, %{"end_count" => 5, "ends_at" => nil}, []} = read("FREQ=DAILY;COUNT=5")

      assert {:ok, %{"ends_at" => "2026-12-31T23:59:59Z"}, []} =
               read("FREQ=DAILY;UNTIL=20261231")

      assert {:ok, %{"ends_at" => "2026-12-31T10:00:00Z"}, []} =
               read("FREQ=DAILY;UNTIL=20261231T100000Z")
    end

    test "from completion, on the date it names" do
      assert {:ok, %{"mode" => "on_completion", "anchor" => "defer"}, []} =
               read("FREQ=WEEKLY", %{
                 "repeat_schedule" => "from-completion",
                 "repeat_anchor" => "defer-date",
                 "start" => @due
               })
    end

    test "older backups say it with a method" do
      older = %{"repeat_schedule" => nil, "repeat_anchor" => nil, "start" => @due}

      assert {:ok, %{"mode" => "on_completion", "anchor" => "defer"}, []} =
               read("FREQ=DAILY", Map.put(older, "repeat_method", "start-after-completion"))

      assert {:ok, %{"mode" => "on_completion", "anchor" => "due"}, []} =
               read("FREQ=DAILY", Map.put(older, "repeat_method", "due-after-completion"))

      assert {:ok, %{"mode" => "regular", "anchor" => "due"}, []} =
               read("FREQ=DAILY", Map.put(older, "repeat_method", "fixed"))
    end

    test "the oldest keep a short interval" do
      assert {:ok, %{"frequency" => "weeks", "interval" => 2}, []} =
               read("@2w", %{"repeat_schedule" => nil, "repeat_anchor" => nil})
    end
  end

  describe "closest fit" do
    test "from completion keeps the interval but not the days" do
      assert {:ok, %{"mode" => "on_completion", "weekdays" => []} = rule, [change]} =
               read("FREQ=WEEKLY;BYDAY=TU", %{"repeat_schedule" => "from-completion"})

      assert change =~ "without its days"
      assert Series.valid_rule?(rule)
    end

    test "a regular repeat that did not catch up now does" do
      assert {:ok, _rule, [change]} = read("FREQ=DAILY", %{"repeat_catch_up" => "false"})
      assert change =~ "skips dates that have passed"

      assert {:ok, _rule, []} = read("FREQ=DAILY", %{"repeat_catch_up" => "true"})
    end
  end

  describe "not read" do
    test "parts Marskal has no place for" do
      for rule <- [
            "FREQ=DAILY;BYHOUR=9",
            "FREQ=YEARLY;BYWEEKNO=20",
            "FREQ=MONTHLY;BYDAY=MO",
            "FREQ=MONTHLY;BYDAY=MO,WE;BYSETPOS=2",
            "FREQ=SECONDLY",
            "FREQ=DAILY;INTERVAL=0",
            "every so often"
          ] do
        assert read(rule) == :error, rule
      end
    end

    test "a repeat without the date it moves" do
      assert read("FREQ=DAILY", %{"due" => nil}) == :error
      assert read("FREQ=DAILY", %{"repeat_anchor" => "planned-date"}) == :error
    end

    test "no repeat" do
      assert OmnifocusRecurrence.read(%{"due" => @due}) == :error
    end
  end
end
