defmodule Marskal.DevicesTest do
  use Marskal.DataCase, async: true

  import Marskal.OAuthFixtures

  alias Marskal.Accounts
  alias Marskal.AccountsFixtures
  alias Marskal.Devices

  setup do
    %{user: AccountsFixtures.user_fixture()}
  end

  describe "authenticate/1" do
    test "a live token of a signed-in device gives its user, device, and scopes", %{user: user} do
      tokens = signed_in_device(user, %{"scope" => "offline_access sync:read"})

      assert {:ok, authenticated, device, ["offline_access", "sync:read"]} =
               Devices.authenticate(tokens.access_token)

      assert authenticated.id == user.id
      assert authenticated.preferences.timezone == "Europe/Copenhagen"

      assert device.id == tokens.device.id
      assert %DateTime{} = device.last_used_at
    end

    test "refuses a token Hydra says is not live", %{user: _user} do
      stub_hydra()
      assert Devices.authenticate("ory_at_whatever") == :error
    end

    test "refuses a token whose device was signed out", %{user: user} do
      tokens = signed_in_device(user)
      {:ok, _} = Devices.sign_out(user, tokens.device.id)
      assert Devices.authenticate(tokens.access_token) == :error
    end

    test "refuses a token whose device belongs to someone else", %{user: user} do
      other = AccountsFixtures.user_fixture()
      tokens = signed_in_device(other)
      forged = String.replace(tokens.access_token, other.id, user.id)
      assert Devices.authenticate(forged) == :error
    end

    test "refuses a refresh token or an ID token" do
      stub_hydra(%{
        {"POST", "/admin/oauth2/introspect"} => %{active: true, token_use: "refresh_token"}
      })

      assert Devices.authenticate("ory_rt_whatever") == :error
    end
  end

  describe "signing out" do
    test "one device revokes its consent in Hydra", %{user: user} do
      tokens = signed_in_device(user)
      consent = tokens.device.consent_request_id

      assert {:ok, _} = Devices.sign_out(user, tokens.device.id)
      assert Devices.list(user) == []

      assert_received {:hydra, "DELETE", "/admin/oauth2/auth/sessions/consent",
                       %{"consent_request_id" => ^consent}}
    end

    test "someone else's device is not found", %{user: user} do
      tokens = signed_in_device(AccountsFixtures.user_fixture())
      assert {:error, :not_found} = Devices.sign_out(user, tokens.device.id)
    end

    test "a password change signs out every device", %{user: user} do
      signed_in_device(user)
      signed_in_device(user)

      {:ok, _} = Accounts.update_user_password(user, %{password: "a new password!"})

      assert Devices.list(user) == []
      subject = user.id

      assert_received {:hydra, "DELETE", "/admin/oauth2/auth/sessions/consent",
                       %{"subject" => ^subject, "all" => "true"}}
    end

    test "still holds here when Hydra cannot be reached", %{user: user} do
      tokens = signed_in_device(user)

      stub_hydra(%{
        {"DELETE", "/admin/oauth2/auth/sessions/consent"} => {503, %{error: "unavailable"}}
      })

      assert {:ok, _} = Devices.sign_out(user, tokens.device.id)
      assert Devices.authenticate(tokens.access_token) == :error
    end
  end
end
