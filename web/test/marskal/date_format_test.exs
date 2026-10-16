defmodule Marskal.DateFormatTest do
  use ExUnit.Case, async: true

  alias Marskal.DateFormat

  @date ~D[2026-10-11]
  @time ~T[16:30:00]
  @datetime DateTime.new!(@date, @time, "Europe/Copenhagen")

  test "every locale a user can pick formats every style" do
    for {locale, _region} <- DateFormat.locales(),
        style <- [:weekday, :day_month, :day_month_year, :long, :long_year] do
      assert is_binary(DateFormat.date(@date, style, locale: locale))
      assert is_binary(DateFormat.time(@time, locale: locale))
      assert is_binary(DateFormat.date_time(@datetime, locale: locale))
    end
  end

  test "the locale sets the order and the clock, the words stay English" do
    assert DateFormat.date(@date, :day_month, locale: "en-DK") == "11 Oct"
    assert DateFormat.time(@time, locale: "en-DK") == "16.30"
    assert DateFormat.date_time(@datetime, locale: "en-DK") == "11 Oct 2026, 16.30"

    assert DateFormat.date(@date, :day_month, locale: "en") == "Oct 11"
    assert DateFormat.time(@time, locale: "en") =~ ~r/^4:30\sPM$/u
    assert DateFormat.date(@date, :long_year, locale: "en-GB") == "Sunday, 11 October 2026"
  end

  test "da writes Danish names" do
    assert DateFormat.date(@date, :day_month_year, locale: "da") == "11. okt. 2026"
    assert DateFormat.date(@date, :weekday, locale: "da") == "søn."
    assert DateFormat.time(@time, locale: "da") == "16.30"
  end

  test "without a locale it uses the process's" do
    Marskal.Cldr.put_locale("en-DK")
    assert DateFormat.time(@time) == "16.30"
  end

  test "the Nix build fetches every locale but en, which ex_cldr ships" do
    listed =
      Regex.scan(~r/^\s*"([^"]+)" = "sha256-/m, File.read!("nix/cldr-locales.nix"))
      |> Enum.map(fn [_, locale] -> locale end)
      |> Enum.sort()

    known = for locale <- Marskal.Cldr.known_locale_names(), locale != :en, do: to_string(locale)

    assert listed == Enum.sort(known), "run nix/update-cldr-locales"
  end

  test "each locale has a region name" do
    for {locale, region} <- DateFormat.locales(), do: refute(region == locale)
  end
end
