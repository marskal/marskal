defmodule MarskalWeb.UserLive.SettingsTest do
  use MarskalWeb.ConnCase, async: true

  alias Marskal.Accounts
  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  describe "Settings page" do
    test "sets the day the week starts on", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      assert lv |> form("#preferences_form", preferences: %{week_start: "7"}) |> render_change() =~
               "Preferences saved."

      assert Accounts.preferences(Accounts.get_user!(user.id)).week_start == 7
    end

    test "chooses the page a login opens", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      assert html =~ "Home view"
      assert html =~ ~s(<option selected="" value="open_tasks">Open tasks</option>)

      html =
        lv |> form("#preferences_form", preferences: %{home_view: "inbox"}) |> render_change()

      assert html =~ "Preferences saved."
      assert html =~ ~s(<option selected="" value="inbox">Inbox</option>)

      assert Accounts.preferences(Accounts.get_user!(user.id)).home_view == :inbox
    end

    test "chooses the keyboard map", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      assert html =~ "Keymap"
      assert html =~ ~s(<option selected="" value="standard">Standard</option>)

      html = lv |> form("#preferences_form", preferences: %{keymap: "vim"}) |> render_change()

      assert html =~ "Preferences saved."
      assert html =~ ~s(<option selected="" value="vim">Vim-style</option>)
      assert Accounts.preferences(Accounts.get_user!(user.id)).keymap == :vim
    end

    test "sets the locale dates and times are shown in", %{conn: conn} do
      user = user_fixture()
      zone = Accounts.timezone(user)

      due =
        Marskal.Dates.from_local(
          Date.add(Marskal.Dates.today(zone), 20),
          ~T[16:30:00],
          :due_at,
          zone
        )

      {:ok, _} =
        Marskal.Tasks.create_task(
          user,
          %{title: "Report", inbox: false, due_at: due},
          Ecto.UUID.generate(version: 7)
        )

      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      assert has_element?(lv, "#preferences_form option[value=en-DK]", "Denmark")

      lv |> form("#preferences_form", preferences: %{locale: "en-DK"}) |> render_change()
      assert Accounts.locale(Accounts.get_user!(user.id)) == "en-DK"

      {:ok, lv, _html} = live(conn, ~p"/open")
      assert render(lv) =~ "16.30"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "needs no recent login", %{conn: conn} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(~p"/users/settings")

      assert has_element?(lv, "#preferences_form")
      assert has_element?(lv, "#settings-tabs a[aria-current=page]", "Preferences")
      refute has_element?(lv, "#email_form")
    end
  end
end
