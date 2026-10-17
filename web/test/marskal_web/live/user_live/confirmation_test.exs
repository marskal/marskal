defmodule MarskalWeb.UserLive.ConfirmationTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  alias Marskal.Accounts

  setup do
    user = registered_user_fixture()
    {:ok, token} = Accounts.build_confirmation_token(user)
    %{user: user, token: token}
  end

  test "asks for the account's password", %{conn: conn, user: user, token: token} do
    {:ok, _lv, html} = live(conn, ~p"/users/confirm/#{token}")
    assert html =~ "Confirm your account"
    assert html =~ user.email
  end

  test "confirms and logs in", %{conn: conn, user: user, token: token} do
    {:ok, lv, _html} = live(conn, ~p"/users/confirm/#{token}")

    form =
      form(lv, "#confirmation_form",
        user: %{"token" => token, "password" => valid_user_password()}
      )

    conn = submit_form(form, conn)
    assert redirected_to(conn) == ~p"/open"
    assert Accounts.get_user!(user.id).confirmed_at
  end

  test "sends a bad or used link to log in", %{conn: conn} do
    {:error, {:live_redirect, %{to: path, flash: flash}}} =
      live(conn, ~p"/users/confirm/invalid-token")

    assert path == ~p"/users/log-in"
    assert flash["error"] == "The link is invalid or it has expired."
  end
end
