defmodule MarskalWeb.UserLive.SettingsTest do
  use MarskalWeb.ConnCase, async: true

  alias Marskal.Accounts
  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Change Email"
      assert html =~ "Save Password"
    end

    test "sets the day the week starts on", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      assert lv |> form("#preferences_form", preferences: %{week_start: "7"}) |> render_change() =~
               "UserPreferences saved."

      assert Accounts.preferences(Accounts.get_user!(user.id)).week_start == 7
    end

    test "chooses the page a login opens", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      assert html =~ "Home view"
      assert html =~ ~s(<option selected="" value="open_tasks">Open tasks</option>)

      html =
        lv |> form("#preferences_form", preferences: %{home_view: "inbox"}) |> render_change()

      assert html =~ "UserPreferences saved."
      assert html =~ ~s(<option selected="" value="inbox">Inbox</option>)

      assert Accounts.preferences(Accounts.get_user!(user.id)).home_view == :inbox
    end

    test "chooses the keyboard map", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      assert html =~ "Keymap"
      assert html =~ ~s(<option selected="" value="standard">Standard</option>)

      html = lv |> form("#preferences_form", preferences: %{keymap: "vim"}) |> render_change()

      assert html =~ "UserPreferences saved."
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

    test "redirects if user is not in sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(~p"/users/settings")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert conn.resp_body =~ "You must re-authenticate to access this page."
    end

    test "logging in again goes back to the settings page", %{conn: conn} do
      user = user_fixture() |> set_password()

      conn =
        conn
        |> log_in_user(user,
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> get(~p"/users/settings")

      assert redirected_to(conn) == ~p"/users/log-in"

      conn =
        post(recycle(conn), ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/users/settings"
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user email", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "A link to confirm your email"
      assert Accounts.get_user_by_email(user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "Change Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "Change Email"
      assert result =~ "did not change"
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user password", %{conn: conn, user: user} do
      new_password = valid_user_password()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      form =
        form(lv, "#password_form", %{
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/users/settings"

      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#password_form", %{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token = Accounts.build_update_email_token(%{user | email: email}, user.email)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"info" => message} = flash
      assert message == "Email changed successfully."
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => message} = flash
      assert message == "You must log in to access this page."
    end
  end
end
