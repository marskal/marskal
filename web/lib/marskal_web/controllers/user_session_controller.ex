defmodule MarskalWeb.UserSessionController do
  use MarskalWeb, :controller

  alias Marskal.Accounts
  alias Marskal.Accounts.User
  alias MarskalWeb.{UserAuth, UserNotifier}
  alias MarskalWeb.UserLive.CheckEmail

  def create(conn, params) do
    create(conn, params, gettext("Welcome back!"))
  end

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    case Accounts.get_user_by_email_and_password(email, password) do
      %User{confirmed_at: nil} = user ->
        # The password is right, so this is the account's maker: send a
        # fresh link. Unless one went out a minute ago.
        with {:ok, token} <- Accounts.build_confirmation_token(user) do
          UserNotifier.deliver_confirmation_instructions(user, token)
        end

        conn
        |> CheckEmail.put_flash_for("unconfirmed", user.email)
        |> redirect(to: ~p"/users/check-email")

      %User{} = user ->
        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      nil ->
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, gettext("Invalid email or password"))
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def confirm(conn, %{"user" => %{"token" => token, "password" => password} = user_params}) do
    case Accounts.confirm_user(token, password) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, gettext("Your account is confirmed."))
        |> UserAuth.log_in_user(user, user_params)

      {:error, :invalid_password} ->
        conn
        |> put_flash(:error, gettext("That isn't this account's password."))
        |> redirect(to: ~p"/users/confirm/#{token}")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, gettext("The link is invalid or it has expired."))
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, gettext("Password updated successfully!"))
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Logged out successfully."))
    |> UserAuth.log_out_user()
  end
end
