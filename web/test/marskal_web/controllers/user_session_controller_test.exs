defmodule MarskalWeb.UserSessionControllerTest do
  use MarskalWeb.ConnCase, async: true

  import Marskal.AccountsFixtures
  import Swoosh.TestAssertions

  alias Marskal.Accounts

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  describe "POST /users/log-in - email and password" do
    test "logs the user in", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/open"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/open")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_marskal_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/open"
    end

    test "opens the page chosen in preferences", %{conn: conn, user: user} do
      user = set_password(user)

      {:ok, _} =
        Accounts.update_preferences(user, %{home_view: :agenda}, Ecto.UUID.generate(version: 7))

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/agenda"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "redirects to login page with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in?mode=password", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/log-in - unconfirmed account" do
    test "refuses to log in and sends a fresh link", %{conn: conn} do
      user = registered_user_fixture()

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/check-email"
      assert Phoenix.Flash.get(conn.assigns.flash, :check_email) == "unconfirmed"
      assert_email_sent(to: [{"", user.email}], subject: "Confirm your Marskal account")
    end

    test "sends at most one link a minute", %{conn: conn} do
      user = registered_user_fixture()
      {:ok, _token} = Accounts.build_confirmation_token(user)

      post(conn, ~p"/users/log-in", %{
        "user" => %{"email" => user.email, "password" => valid_user_password()}
      })

      assert_no_email_sent()
    end
  end

  describe "POST /users/confirm" do
    setup do
      user = registered_user_fixture()
      {:ok, token} = Accounts.build_confirmation_token(user)
      %{pending: user, token: token}
    end

    test "confirms with the password and logs in", %{conn: conn, pending: user, token: token} do
      conn =
        post(conn, ~p"/users/confirm", %{
          "user" => %{"token" => token, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/open"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Your account is confirmed."
      assert Accounts.get_user!(user.id).confirmed_at
    end

    test "sends a wrong password back to the link", %{conn: conn, pending: user, token: token} do
      conn =
        post(conn, ~p"/users/confirm", %{
          "user" => %{"token" => token, "password" => "wrong one!"}
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/confirm/#{token}"
      refute Accounts.get_user!(user.id).confirmed_at
    end

    test "refuses a bad link", %{conn: conn} do
      conn =
        post(conn, ~p"/users/confirm", %{
          "user" => %{"token" => "invalid", "password" => valid_user_password()}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
