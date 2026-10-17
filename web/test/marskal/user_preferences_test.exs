defmodule Marskal.UserPreferencesTest do
  use Marskal.DataCase, async: true

  alias Marskal.Accounts
  alias Marskal.Accounts.UserPreferences
  alias Marskal.AccountsFixtures
  alias Marskal.Sync
  alias Marskal.Sync.Push

  setup do
    %{user: AccountsFixtures.user_fixture(), other: AccountsFixtures.user_fixture()}
  end

  test "every user has one row, made with the user", %{user: user} do
    assert %UserPreferences{
             timezone: "Europe/Copenhagen",
             week_start: 1,
             locale: "en-150",
             home_view: :open_tasks,
             keymap: :standard
           } = Accounts.preferences(user)

    assert Repo.aggregate(where(UserPreferences, user_id: ^user.id), :count) == 1
  end

  test "a change goes through the change feed, and a bad value is refused", %{user: user} do
    {:ok, preferences} =
      Accounts.update_preferences(
        user,
        %{timezone: "America/New_York", week_start: 7, home_view: :agenda},
        command()
      )

    assert [
             %{
               "id" => id,
               "timezone" => "America/New_York",
               "week_start" => 7,
               "home_view" => "agenda"
             }
           ] = Sync.pull(user, 0).rows["user_preferences"]

    assert id == preferences.id
    assert Sync.pull(user, 0).user.timezone == "America/New_York"

    assert {:error, changeset} =
             Accounts.update_preferences(
               user,
               %{timezone: "Mars/Olympus", week_start: 8, home_view: "later"},
               command()
             )

    assert "is not a known time zone" in errors_on(changeset).timezone
    assert "is invalid" in errors_on(changeset).week_start
    assert "is invalid" in errors_on(changeset).home_view

    assert {:error, changeset} = Accounts.update_preferences(user, %{keymap: "emacs"}, command())
    assert "is invalid" in errors_on(changeset).keymap
  end

  test "the keymap syncs, and a client may patch it", %{user: user} do
    {:ok, _} = Accounts.update_preferences(user, %{keymap: :vim}, command())

    assert [%{"keymap" => "vim"}] = Sync.pull(user, 0).rows["user_preferences"]

    [%{"id" => id}] = Sync.pull(user, nil).rows["user_preferences"]

    assert [%{status: "applied"}] =
             Push.push(user, [push(id, "patch", %{"keymap" => "standard"})])

    assert Accounts.preferences(user).keymap == :standard
  end

  test "the locale is one Marskal.Cldr knows, and syncs", %{user: user} do
    {:ok, _} = Accounts.update_preferences(user, %{locale: "en-DK"}, command())

    assert Accounts.locale(user) == "en-DK"
    assert [%{"locale" => "en-DK"}] = Sync.pull(user, 0).rows["user_preferences"]

    assert {:error, changeset} = Accounts.update_preferences(user, %{locale: "da-DK"}, command())
    assert "is invalid" in errors_on(changeset).locale

    [%{"id" => id}] = Sync.pull(user, nil).rows["user_preferences"]

    assert [%{status: "applied"}] =
             Push.push(user, [push(id, "patch", %{"locale" => "en-SE"})])

    assert Accounts.locale(user) == "en-SE"
  end

  test "a client patches its own row, and cannot insert or delete one", %{
    user: user,
    other: other
  } do
    [%{"id" => id}] = Sync.pull(user, nil).rows["user_preferences"]
    theirs = Accounts.preferences(other).id

    assert [
             %{status: "applied"},
             %{status: "rejected", reason: "not_found"},
             %{status: "rejected", reason: "field_not_allowed"},
             %{status: "rejected", reason: "invalid"},
             %{status: "rejected", reason: "field_not_allowed"},
             %{status: "rejected", reason: "invalid"}
           ] =
             Push.push(user, [
               push(id, "patch", %{"week_start" => 6, "home_view" => "inbox"}),
               push(theirs, "patch", %{"week_start" => 6}),
               push(id, "patch", %{"discarded_at" => "2026-10-08T10:00:00Z"}),
               push(id, "patch", %{"home_view" => "later"}),
               push(Ecto.UUID.generate(version: 7), "insert", %{"week_start" => 6}),
               push(Ecto.UUID.generate(version: 7), "insert", %{})
             ])

    assert Accounts.preferences(user).week_start == 6
    assert Accounts.preferences(user).home_view == :inbox
    assert Accounts.preferences(other).week_start == 1
  end

  defp push(id, op, fields),
    do: %{
      "id" => command(),
      "entity" => "user_preferences",
      "entity_id" => id,
      "op" => op,
      "fields" => fields
    }

  defp command, do: Ecto.UUID.generate(version: 7)
end
