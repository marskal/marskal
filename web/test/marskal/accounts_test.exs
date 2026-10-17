defmodule Marskal.AccountsTest do
  use Marskal.DataCase

  alias Marskal.Accounts

  import Marskal.AccountsFixtures
  alias Marskal.Accounts.{User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@marskal.example")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@marskal.example", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture() |> set_password()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture() |> set_password()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email and password to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert "can't be blank" in errors_on(changeset).email
      assert "can't be blank" in errors_on(changeset).password
    end

    test "validates email when given" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users with a password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert user.hashed_password
      assert Accounts.timezone(user) == "Europe/Copenhagen"
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "build_update_email_token/2" do
    test "stores a token for the new address" do
      user = user_fixture()
      token = Accounts.build_update_email_token(user, "current@marskal.example")

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@marskal.example"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token = Accounts.build_update_email_token(%{user | email: email}, user.email)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@marskal.example"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(
          %User{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_, _}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "confirm_user/2" do
    setup do
      user = registered_user_fixture()
      {:ok, token} = Accounts.build_confirmation_token(user)
      %{user: user, token: token}
    end

    test "registration leaves the account unconfirmed", %{user: user} do
      refute user.confirmed_at
      assert user.hashed_password
    end

    test "confirms with the account's password and ends its tokens", %{user: user, token: token} do
      assert Accounts.get_user_by_confirmation_token(token).id == user.id
      assert {:ok, {confirmed, [_token]}} = Accounts.confirm_user(token, valid_user_password())
      assert confirmed.confirmed_at
      refute Accounts.get_user_by_confirmation_token(token)
      assert {:error, :not_found} = Accounts.confirm_user(token, valid_user_password())
    end

    test "refuses another password", %{user: user, token: token} do
      assert {:error, :invalid_password} = Accounts.confirm_user(token, "not the password")
      refute Repo.get!(User, user.id).confirmed_at
    end

    test "refuses a bad or expired token", %{token: token} do
      assert {:error, :not_found} = Accounts.confirm_user("oops", valid_user_password())
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert {:error, :not_found} = Accounts.confirm_user(token, valid_user_password())
    end

    test "refuses a token sent to an address the account no longer has", %{
      user: user,
      token: token
    } do
      Repo.update_all(from(u in User, where: u.id == ^user.id), set: [email: unique_user_email()])
      assert {:error, :not_found} = Accounts.confirm_user(token, valid_user_password())
    end

    test "sends one link a minute", %{user: user} do
      assert {:error, :sent_recently} = Accounts.build_confirmation_token(user)
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert {:ok, _token} = Accounts.build_confirmation_token(user)
    end
  end

  describe "delete_unconfirmed_users/1" do
    test "deletes accounts unconfirmed past the link's life" do
      stale = registered_user_fixture()
      fresh = registered_user_fixture()
      confirmed = user_fixture()

      old = ~U[2020-01-01 00:00:00Z]

      Repo.update_all(from(u in User, where: u.id in ^[stale.id, confirmed.id]),
        set: [inserted_at: old]
      )

      assert {1, _} = Accounts.delete_unconfirmed_users()
      refute Repo.get(User, stale.id)
      assert Repo.get(User, fresh.id)
      assert Repo.get(User, confirmed.id)
    end
  end

  describe "reset_user_password/2" do
    test "sets the password and ends every token" do
      user = password_user_fixture()
      _session = Accounts.generate_user_session_token(user)
      {:ok, token} = Accounts.build_reset_password_token(user)
      assert Accounts.get_user_by_reset_password_token(token).id == user.id

      assert {:ok, {_user, [_session, _reset]}} =
               Accounts.reset_user_password(user, %{password: "a new valid password"})

      refute Accounts.get_user_by_reset_password_token(token)
      refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())
      assert Accounts.get_user_by_email_and_password(user.email, "a new valid password")
    end

    test "confirms the account and replaces the password someone else set" do
      squatted = registered_user_fixture()
      {:ok, token} = Accounts.build_reset_password_token(squatted)
      user = Accounts.get_user_by_reset_password_token(token)

      assert {:ok, {user, _expired}} =
               Accounts.reset_user_password(user, %{password: "the owner's password"})

      assert user.confirmed_at
      refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "validates the password" do
      user = user_fixture()
      assert {:error, changeset} = Accounts.reset_user_password(user, %{password: "short"})
      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end

    test "refuses a bad or expired token" do
      user = user_fixture()
      {:ok, token} = Accounts.build_reset_password_token(user)
      refute Accounts.get_user_by_reset_password_token("oops")
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_reset_password_token(token)
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end
end
