defmodule Marskal.Collation do
  @moduledoc """
  Name order the user sees (ADR 0034).

  The database sorts text by code point, which puts `Zebra` before
  `apple` and `Å` before `Æ`. A list sorted by name for the user sorts with
  an ICU collation picked from their `locale` preference by a fixed map:
  Danish letter order for `da` and `en-DK`, English for the other locales.
  The collation name never comes from the string itself. A new locale that
  needs another order gets a line here.
  """

  import Ecto.Query

  @danish ~w(da en-DK)

  @doc ~s(The ICU collation for a locale: `"da-x-icu"` or `"en-x-icu"`.)
  def for_locale(locale) when locale in @danish, do: "da-x-icu"
  def for_locale(_locale), do: "en-x-icu"

  @doc """
  Orders `query` by `field` of its first binding, in the locale's
  collation. A fragment needs its SQL at compile time, so each collation
  has its own clause.
  """
  def order_by_name(query, field, locale) do
    case for_locale(locale) do
      "da-x-icu" ->
        order_by(query, [r], asc: fragment(~s|? COLLATE "da-x-icu"|, field(r, ^field)))

      "en-x-icu" ->
        order_by(query, [r], asc: fragment(~s|? COLLATE "en-x-icu"|, field(r, ^field)))
    end
  end
end
