defmodule Marskal.Cldr do
  @moduledoc """
  Locale data for formatting dates and times (ADR 0027).

  The words stay English, so the locales are English ones whose region sets
  the conventions: the order of day and month, the clock, and the
  separators. ex_cldr downloads their data into `priv/cldr` when it
  compiles; the Nix build fetches it by the hashes in
  `nix/cldr-locales.nix` instead.
  """

  @locales ~w(en en-150 en-GB en-IE en-AU en-NZ en-CA en-IN en-ZA en-AT en-BE en-CH en-DE
              en-DK en-ES en-FI en-FR en-IT en-NL en-NO en-PL en-SE)

  use Cldr,
    locales: @locales,
    default_locale: "en-150",
    data_dir: "priv/cldr",
    force_locale_download: false,
    providers: [Cldr.Number, Cldr.Calendar, Cldr.DateTime]
end
