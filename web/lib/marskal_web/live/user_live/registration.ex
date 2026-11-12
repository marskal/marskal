defmodule MarskalWeb.UserLive.Registration do
  use MarskalWeb, :live_view

  alias Marskal.Accounts
  alias Marskal.Accounts.User
  alias MarskalWeb.UserLive.CheckEmail
  alias MarskalWeb.UserNotifier

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} inspector={assigns[:inspector]}>
      <h1>{gettext("Register")}</h1>
      <p class="lede">
        {gettext("Already registered?")}
        <.link navigate={~p"/users/log-in"}>{gettext("Log in")}</.link>
      </p>

      <.form
        for={@form}
        id="registration_form"
        class="auth"
        phx-submit="save"
        phx-change="validate"
      >
        <div>
          <label for={@form[:email].id}>Email</label>
          <input
            type="email"
            name={@form[:email].name}
            id={@form[:email].id}
            value={@form[:email].value}
            autocomplete="username"
            required
            autofocus
          />
          <p :for={error <- @form[:email].errors} class="field-error">{translate_error(error)}</p>
        </div>
        <div>
          <label for={@form[:name].id}>{gettext("Name (optional)")}</label>
          <input
            type="text"
            name={@form[:name].name}
            id={@form[:name].id}
            value={@form[:name].value}
            autocomplete="name"
            maxlength="100"
          />
          <p :for={error <- @form[:name].errors} class="field-error">{translate_error(error)}</p>
        </div>
        <div>
          <label for={@form[:password].id}>Password</label>
          <input
            type="password"
            name={@form[:password].name}
            id={@form[:password].id}
            autocomplete="new-password"
            required
          />
          <p :for={error <- @form[:password].errors} class="field-error">{translate_error(error)}</p>
        </div>
        <button type="submit">Create account</button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: MarskalWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{}, %{})

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, token} = Accounts.build_confirmation_token(user)
        UserNotifier.deliver_confirmation_instructions(user, token)

        {:noreply,
         socket
         |> CheckEmail.put_flash_for("registered", user.email)
         |> push_navigate(to: ~p"/users/check-email")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
