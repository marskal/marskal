defmodule Marskal.DateInputTest do
  @moduledoc """
  The rules of ADR 0032 that cut across the shared vectors in
  `core/fixtures/date_input.json`, which `Marskal.FixturesTest` runs.
  """

  use ExUnit.Case, async: true

  alias Marskal.DateInput

  @friday ~N[2026-10-16 10:37:12]

  defp parse(text, opts \\ []),
    do: DateInput.parse(text, @friday, Keyword.merge([week_start: 1, order: :dmy], opts))

  test "every weekday name reads as a day in the coming week" do
    for {names, language} <- [
          {~w(mon tue wed thu fri sat sun), "en"},
          {~w(mandag tirsdag onsdag torsdag fredag lørdag søndag), "da"}
        ],
        name <- names do
      assert {:ok, date, nil} = parse(name, language: language)
      assert Date.diff(date, ~D[2026-10-16]) in 1..7, name
    end
  end

  test "every month name reads with a day" do
    english = [jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10]
    danish = [januar: 1, marts: 3, maj: 5, juni: 6, juli: 7, okt: 10, oktober: 10]

    for {months, language} <- [{english, "en"}, {danish, "da"}], {name, month} <- months do
      assert {:ok, %Date{month: ^month, day: 2}, nil} = parse("2 #{name}", language: language),
             "#{name}"
    end
  end

  test "Danish words are read only with a Danish locale" do
    for text <- ["i morgen", "fredag", "maj 2", "om 2 dage", "nu"] do
      assert parse(text, language: "en") == :error, text
      assert {:ok, _, _} = parse(text, language: "da"), text
    end
  end

  test "a field's own label reads back as the same day, in each order" do
    assert parse("16 Oct 2026") == {:ok, ~D[2026-10-16], nil}
    assert parse("Oct 16, 2026", order: :mdy) == {:ok, ~D[2026-10-16], nil}
    assert parse("16 Oct 2026, 4:30 PM") == {:ok, ~D[2026-10-16], ~T[16:30:00]}
  end

  test "text decomposed differently is the same" do
    decomposed = "i ga" <> <<0x030A::utf8>> <> "r"
    assert parse(decomposed, language: "da") == {:ok, ~D[2026-10-15], nil}
  end

  test "seconds of now are dropped" do
    assert parse("now") == {:ok, ~D[2026-10-16], ~T[10:37:00]}
    assert parse("1h") == {:ok, ~D[2026-10-16], ~T[11:37:00]}
  end
end
