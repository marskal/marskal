defmodule Marskal.DateInputTest do
  @moduledoc """
  The rules of ADR 0032 that cut across the shared vectors in
  `sync/fixtures/date_input.json`, which `Marskal.SyncFixturesTest` runs.
  """

  use ExUnit.Case, async: true

  alias Marskal.DateInput

  @friday ~N[2026-10-16 10:37:12]

  defp parse(text, opts \\ []),
    do: DateInput.parse(text, @friday, Keyword.merge([week_start: 1, order: :dmy], opts))

  test "every weekday name reads as a day in the coming week" do
    for name <- ~w(mon tue wed thu fri sat sun mandag tirsdag onsdag torsdag fredag lørdag søndag) do
      assert {:ok, date, nil} = parse(name)
      assert Date.diff(date, ~D[2026-10-16]) in 1..7, name
    end
  end

  test "every month name reads with a day" do
    for {name, month} <-
          [jan: 1, feb: 2, mar: 3, apr: 4, maj: 5, jun: 6, jul: 7, aug: 8] ++
            [sep: 9, okt: 10, nov: 11, dec: 12, marts: 3, may: 5, october: 10] do
      assert {:ok, %Date{month: ^month, day: 2}, nil} = parse("2 #{name}"), "#{name}"
    end
  end

  test "a field's own label reads back as the same day, in each order" do
    assert parse("16 Oct 2026") == {:ok, ~D[2026-10-16], nil}
    assert parse("Oct 16, 2026", order: :mdy) == {:ok, ~D[2026-10-16], nil}
    assert parse("16 Oct 2026, 4:30 PM") == {:ok, ~D[2026-10-16], ~T[16:30:00]}
  end

  test "text decomposed differently is the same" do
    assert {:ok, ~D[2026-10-15], nil} = parse("i går")
  end

  test "seconds of now are dropped" do
    assert parse("now") == {:ok, ~D[2026-10-16], ~T[10:37:00]}
    assert parse("1h") == {:ok, ~D[2026-10-16], ~T[11:37:00]}
  end
end
