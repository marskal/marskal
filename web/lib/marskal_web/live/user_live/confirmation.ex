defmodule MarskalWeb.UserLive.Confirmation do
  @moduledoc """
  The link a registration emails. Confirming takes the account's password
  too, so the link alone does not confirm an account someone else made
  with the address (`Marskal.Accounts.confirm_user/2`).
  """

  use MarskalWeb, :live_view

  alias Marskal.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} inspector={assigns[:inspector]}>
      <h1>{gettext("Confirm your account")}</h1>
      <p class="lede">
        {gettext("Enter the password you chose for %{email}.", email: @user.email)}
      </p>

      <.form for={@form} id="confirmation_form" class="auth" action={~p"/users/confirm"}>
        <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
        <div>
          <label for="user_password">{gettext("Password")}</label>
          <input
            type="password"
            name="user[password]"
            id="user_password"
            autocomplete="current-password"
            required
            autofocus
          />
        </div>
        <label>
          <input type="checkbox" name="user[remember_me]" value="true" /> {gettext("Stay logged in")}
        </label>
        <button type="submit">{gettext("Confirm and log in")}</button>
      </.form>
      <p>
        <.link navigate={~p"/users/reset-password"}>{gettext("Forgot your password?")}</.link>
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_confirmation_token(token) do
      {:ok, assign(socket, user: user, form: to_form(%{"token" => token}, as: "user"))}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("The link is invalid or it has expired."))
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end
end
