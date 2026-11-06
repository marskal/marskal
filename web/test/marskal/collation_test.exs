defmodule Marskal.CollationTest do
  use Marskal.DataCase, async: true

  alias Marskal.Accounts
  alias Marskal.AccountsFixtures
  alias Marskal.ProjectFolders

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

  describe "folders by name" do
    @names ["Zebra", "Århus", "apple", "Æble", "Østerbro", "avocado"]

    for locale <- ~w(da en-DK) do
      test "in Danish letter order for #{locale}" do
        assert folder_names(unquote(locale)) ==
                 ["apple", "avocado", "Zebra", "Æble", "Østerbro", "Århus"]
      end
    end

    test "in English letter order for another English locale" do
      assert folder_names("en-GB") ==
               ["Æble", "apple", "Århus", "avocado", "Østerbro", "Zebra"]
    end
  end

  defp folder_names(locale) do
    user = AccountsFixtures.user_fixture()
    {:ok, _} = Accounts.update_preferences(user, %{locale: locale}, command())

    for name <- @names do
      {:ok, _} = ProjectFolders.create_folder(user, %{"name" => name}, command())
    end

    user |> ProjectFolders.list_all() |> Enum.map(& &1.name)
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
