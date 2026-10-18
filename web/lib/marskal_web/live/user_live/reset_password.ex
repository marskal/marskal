defmodule MarskalWeb.UserLive.ResetPassword do
  @moduledoc """
  The link a reset emails: sets a new password, confirms the account if it
  was not, and ends every session (`Marskal.Accounts.reset_user_password/2`).
  """

  use MarskalWeb, :live_view

  alias Marskal.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} inspector={assigns[:inspector]}>
      <h1>{gettext("Choose a new password")}</h1>
      <p class="lede">{gettext("For %{email}.", email: @user.email)}</p>

      <.form
        for={@form}
        id="new_password_form"
        class="auth"
        phx-submit="save"
        phx-change="validate"
      >
        <div>
          <label for={@form[:password].id}>{gettext("New password")}</label>
          <input
            type="password"
            name={@form[:password].name}
            id={@form[:password].id}
            autocomplete="new-password"
            required
            autofocus
          />
          <p :for={error <- @form[:password].errors} class="field-error">{translate_error(error)}</p>
        </div>
        <div>
          <label for={@form[:password_confirmation].id}>{gettext("Confirm new password")}</label>
          <input
            type="password"
            name={@form[:password_confirmation].name}
            id={@form[:password_confirmation].id}
            autocomplete="new-password"
            required
          />
          <p :for={error <- @form[:password_confirmation].errors} class="field-error">
            {translate_error(error)}
          </p>
        </div>
        <button type="submit">{gettext("Set password")}</button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      form = to_form(Accounts.change_user_password(user, %{}, hash_password: false))
      {:ok, assign(socket, user: user, form: form)}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("The link is invalid or it has expired."))
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    form =
      socket.assigns.user
      |> Accounts.change_user_password(params, hash_password: false)
      |> to_form(action: :validate)

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, params) do
      {:ok, {user, expired_tokens}} ->
        MarskalWeb.UserAuth.disconnect_sessions(expired_tokens)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Your password is changed. Log in with the new one."))
         |> put_flash(:email, user.email)
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :insert))}
    end
  end
end
