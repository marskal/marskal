defmodule Marskal.CollationTest do
  use Marskal.DataCase, async: true

  # ADR 0034. A cluster made with devenv's old `--locale=C` fails here:
  # make it again.
  test "the database uses the built-in provider with PG_UNICODE_FAST" do
    assert %{rows: [["b", "PG_UNICODE_FAST", "UTF8"]]} =
             Repo.query!("""
             SELECT datlocprovider::text, datlocale, pg_encoding_to_char(encoding)
             FROM pg_database WHERE datname = current_database()
             """)
  end

  test "text sorts by code point and citext folds beyond ASCII" do
    assert %{rows: [[true, true, false, true]]} =
             Repo.query!("""
             SELECT 'Zebra' < 'apple', 'å' < 'æ',
                    'ß'::citext = 'ss'::citext, 'Æble'::citext = 'æble'::citext
             """)
  end
end
