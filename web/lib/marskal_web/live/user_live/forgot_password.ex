defmodule MarskalWeb.UserLive.ForgotPassword do
  @moduledoc """
  Asks for an address and emails it a reset link. The answer is the same
  whether or not the address has an account.
  """

  use MarskalWeb, :live_view

  alias Marskal.Accounts
  alias MarskalWeb.UserLive.CheckEmail
  alias MarskalWeb.UserNotifier

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} inspector={assigns[:inspector]}>
      <h1>{gettext("Reset your password")}</h1>
      <p class="lede">{gettext("We'll email you a link to choose a new one.")}</p>

      <.form for={@form} id="reset_password_form" class="auth" phx-submit="send">
        <div>
          <label for="user_email">{gettext("Email")}</label>
          <input
            type="email"
            name="user[email]"
            id="user_email"
            value={@form[:email].value}
            autocomplete="username"
            required
            autofocus
          />
        </div>
        <button type="submit">{gettext("Send the link")}</button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email = get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])
    {:ok, assign(socket, form: to_form(%{"email" => email}, as: "user"))}
  end

  @impl true
  def handle_event("send", %{"user" => %{"email" => email}}, socket) do
    with %Accounts.User{} = user <- Accounts.get_user_by_email(email),
         {:ok, token} <- Accounts.build_reset_password_token(user) do
      UserNotifier.deliver_reset_password_instructions(user, token)
    end

    {:noreply,
     socket
     |> CheckEmail.put_flash_for("reset_password", email)
     |> push_navigate(to: ~p"/users/check-email")}
  end
end
