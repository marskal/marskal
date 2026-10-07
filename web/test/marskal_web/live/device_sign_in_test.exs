defmodule MarskalWeb.DeviceSignInTest do
  @moduledoc "The web app as Hydra's login, consent, and device UI (ADR 0021)."

  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.OAuthFixtures

  alias Marskal.Devices
  alias MarskalWeb.APIAuth

  describe "device verification" do
    setup :register_and_log_in_user

    test "without a challenge, starts at Hydra", %{conn: conn} do
      stub_hydra()

      assert {:error,
              {:redirect, %{to: "http://hydra.test/oauth2/device/verify?user_code=BCDFGHJK"}}} =
               live(conn, ~p"/device?user_code=BCDFGHJK")
    end

    test "confirming the code accepts it in Hydra, on submit only", %{conn: conn} do
      stub_hydra()
      {:ok, lv, html} = live(conn, ~p"/device?device_challenge=dc1&user_code=BCDFGHJK")

      assert html =~ "BCDFGHJK"
      refute_received {:hydra, _, _, _}

      assert {:error, {:redirect, %{to: "http://hydra.test/next"}}} =
               lv |> form("#user-code-form", %{"user_code" => "bcdf-ghjk"}) |> render_submit()

      assert_received {:hydra, "PUT", "/admin/oauth2/auth/requests/device/accept",
                       %{"device_challenge" => "dc1", "body" => %{"user_code" => "BCDFGHJK"}}}
    end

    test "a wrong code says so", %{conn: conn} do
      stub_hydra(%{
        {"PUT", "/admin/oauth2/auth/requests/device/accept"} => {400, %{error: "invalid_request"}}
      })

      {:ok, lv, _html} = live(conn, ~p"/device?device_challenge=dc1")

      assert lv |> form("#user-code-form", %{"user_code" => "XXXX"}) |> render_submit() =~
               "That code is not right"
    end

    test "the success and error pages", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/device/done?client_id=marskal")
      assert html =~ "go back to your device"

      {:ok, _lv, html} =
        live(conn, ~p"/oauth/error?error=access_denied&error_description=Denied.")

      assert html =~ "Denied."
    end
  end

  describe "login" do
    setup :register_and_log_in_user

    test "is accepted for the signed-in user", %{conn: conn, user: user} do
      stub_hydra(%{{"GET", "/admin/oauth2/auth/requests/login"} => %{skip: false, subject: ""}})

      conn = get(conn, ~p"/oauth/login?login_challenge=lc1")
      assert redirected_to(conn) == "http://hydra.test/next"

      subject = user.id

      assert_received {:hydra, "PUT", "/admin/oauth2/auth/requests/login/accept",
                       %{"login_challenge" => "lc1", "body" => %{"subject" => ^subject}}}
    end

    test "a remembered login for someone else is rejected", %{conn: conn} do
      stub_hydra(%{
        {"GET", "/admin/oauth2/auth/requests/login"} => %{skip: true, subject: "someone"}
      })

      get(conn, ~p"/oauth/login?login_challenge=lc1")
      assert_received {:hydra, "PUT", "/admin/oauth2/auth/requests/login/reject", _}
    end
  end

  test "signed out, login asks to log in and comes back to the challenge" do
    conn = build_conn() |> get(~p"/oauth/login?login_challenge=lc1")
    assert redirected_to(conn) == ~p"/users/log-in"
    assert get_session(conn, :user_return_to) == "/oauth/login?login_challenge=lc1"
  end

  describe "consent" do
    setup :register_and_log_in_user

    setup %{user: user} do
      stub_hydra(%{
        {"GET", "/admin/oauth2/auth/requests/consent"} => %{
          subject: user.id,
          consent_request_id: "cr1",
          client: %{client_id: "marskal-terminal", client_name: "Marskal for the terminal"},
          requested_scope: ["offline_access", "sync:read", "sync:write"]
        }
      })

      :ok
    end

    test "allowing names and records the device, and stamps its id on the tokens",
         %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/oauth/consent?consent_challenge=cc1")
      assert html =~ "Allow Marskal for the terminal?"
      assert html =~ "Add and change your tasks"

      assert {:error, {:redirect, %{to: "http://hydra.test/next"}}} =
               lv |> form("#consent-form", %{"name" => "Laptop"}) |> render_submit()

      assert [%{name: "Laptop", consent_request_id: "cr1", id: device_id}] = Devices.list(user)

      assert_received {:hydra, "PUT", "/admin/oauth2/auth/requests/consent/accept",
                       %{"body" => %{"grant_scope" => scopes, "remember" => false} = body}}

      assert scopes == ["offline_access", "sync:read", "sync:write"]
      assert body["session"]["access_token"]["device_id"] == device_id
    end

    test "denying records nothing", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/oauth/consent?consent_challenge=cc1")

      assert {:error, {:redirect, %{to: "http://hydra.test/next"}}} =
               lv |> element("button", "Deny") |> render_click()

      assert Devices.list(user) == []
      assert_received {:hydra, "PUT", "/admin/oauth2/auth/requests/consent/reject", _}
    end
  end

  test "consent for another subject goes to the error page", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    stub_hydra(%{
      {"GET", "/admin/oauth2/auth/requests/consent"} => %{subject: "someone-else", client: %{}}
    })

    assert {:error, {:live_redirect, %{to: "/oauth/error?error=consent_failed"}}} =
             live(conn, ~p"/oauth/consent?consent_challenge=cc1")
  end

  test "the metadata points at Hydra", %{conn: conn} do
    conn = get(conn, ~p"/.well-known/oauth-authorization-server")
    assert redirected_to(conn) == "http://hydra.test/.well-known/oauth-authorization-server"
  end

  describe "settings" do
    setup :register_and_log_in_user

    test "lists devices and signs one out", %{conn: conn, user: user} do
      tokens = signed_in_device(user)
      {:ok, lv, html} = live(conn, ~p"/users/settings")
      assert html =~ "marskal on laptop"

      refute lv |> element("#devices button", "Sign out") |> render_click() =~ "marskal on laptop"
      assert Devices.authenticate(tokens.access_token) == :error
    end
  end

  describe "bearer tokens" do
    test "a live token sets the user, device, and scopes", %{conn: conn} do
      user = Marskal.AccountsFixtures.user_fixture()
      tokens = signed_in_device(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> tokens.access_token)
        |> APIAuth.call([])

      refute conn.halted
      assert conn.assigns.current_scope.user.id == user.id
      assert conn.assigns.device.id == tokens.device.id
      refute conn |> APIAuth.require_scope("sync:write") |> Map.get(:halted)
    end

    test "a missing or unknown token is 401", %{conn: conn} do
      stub_hydra()
      missing = APIAuth.call(conn, [])
      assert missing.status == 401
      assert get_resp_header(missing, "www-authenticate") == [~s(Bearer realm="marskal")]

      unknown =
        build_conn()
        |> put_req_header("authorization", "Bearer ory_at_nope")
        |> APIAuth.call([])

      assert unknown.status == 401
      assert [challenge] = get_resp_header(unknown, "www-authenticate")
      assert challenge =~ ~s(error="invalid_token")
    end

    test "a token without the scope is 403", %{conn: conn} do
      tokens =
        signed_in_device(Marskal.AccountsFixtures.user_fixture(), %{
          "scope" => "offline_access sync:read"
        })

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> tokens.access_token)
        |> APIAuth.call([])
        |> APIAuth.require_scope("sync:write")

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body) == %{"error" => "insufficient_scope"}
    end
  end
end
