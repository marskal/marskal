defmodule MarskalWeb.UserLive.Registration do
  use MarskalWeb, :live_view

  alias Marskal.Accounts
  alias Marskal.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} inspector={assigns[:inspector]}>
      <h1>Register</h1>
      <p class="lede">
        Already registered? <.link navigate={~p"/users/log-in"}>Log in</.link>
      </p>

      <.form
        for={@form}
        id="registration_form"
        class="auth"
        action={~p"/users/log-in"}
        phx-submit="save"
        phx-change="validate"
        phx-trigger-action={@trigger_submit}
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

    {:ok,
     socket
     |> assign(:trigger_submit, false)
     |> assign_form(changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, _user} ->
        changeset = Accounts.change_user_registration(%User{}, user_params)

        {:noreply,
         socket
         |> assign(:trigger_submit, true)
         |> assign_form(changeset)}

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
