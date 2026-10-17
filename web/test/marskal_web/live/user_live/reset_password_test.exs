defmodule MarskalWeb.UserLive.ResetPasswordTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures
  import Swoosh.TestAssertions

  alias Marskal.Accounts

  describe "forgot password" do
    test "the log-in page links to it", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")
      assert has_element?(lv, ~s|a[href="/users/reset-password"]|)
    end

    test "emails a link to an account's address", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, check, html} =
        lv
        |> form("#reset_password_form", user: %{"email" => user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/check-email")

      assert html =~ "we&#39;ve sent it a link to choose a new password"
      refute has_element?(check, "form")

      assert_email_sent(fn sent ->
        assert sent.to == [{"", user.email}]
        assert sent.text_body =~ "/users/reset-password/"
      end)
    end

    test "says the same for an unknown address and sends nothing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, _check, html} =
        lv
        |> form("#reset_password_form", user: %{"email" => "nobody@marskal.example"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/check-email")

      assert html =~ "we&#39;ve sent it a link to choose a new password"
      assert_no_email_sent()
    end
  end

  describe "reset password" do
    setup do
      user = password_user_fixture()
      {:ok, token} = Accounts.build_reset_password_token(user)
      %{user: user, token: token}
    end

    test "validates as you type", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      html =
        lv
        |> form("#new_password_form", user: %{"password" => "short"})
        |> render_change()

      assert html =~ "should be at least 12 character(s)"
    end

    test "sets the new password", %{conn: conn, user: user, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      {:ok, _login, html} =
        lv
        |> form("#new_password_form",
          user: %{
            "password" => "a new valid password",
            "password_confirmation" => "a new valid password"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Your password is changed."
      assert Accounts.get_user_by_email_and_password(user.email, "a new valid password")
    end

    test "sends a bad link to log in", %{conn: conn} do
      {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/users/reset-password/oops")
      assert path == ~p"/users/log-in"
    end
  end

  describe "check email" do
    test "goes to log in without a step to report, as after a reload", %{conn: conn} do
      {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/users/check-email")
      assert path == ~p"/users/log-in"
    end
  end
end
