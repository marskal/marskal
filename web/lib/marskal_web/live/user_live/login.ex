defmodule MarskalWeb.UserLive.Login do
  use MarskalWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1>Log in</h1>
      <p class="lede">
        <%= if @current_scope && @current_scope.user do %>
          Confirm your password to continue.
        <% else %>
          No account yet? <.link navigate={~p"/users/register"}>Register</.link>
        <% end %>
      </p>

      <.form
        for={@form}
        id="login_form_password"
        class="auth"
        action={~p"/users/log-in"}
        phx-submit="submit_password"
        phx-trigger-action={@trigger_submit}
      >
        <div>
          <label for="user_email">Email</label>
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
        <div>
          <label for="user_password">Password</label>
          <input
            type="password"
            name="user[password]"
            id="user_password"
            autocomplete="current-password"
            required
          />
        </div>
        <label>
          <input type="checkbox" name="user[remember_me]" value="true" /> Stay logged in
        </label>
        <button type="submit">Log in</button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end
end
