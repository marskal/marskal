defmodule MarskalWeb.UserLive.Settings do
  use MarskalWeb, :live_view

  on_mount {MarskalWeb.UserAuth, :require_sudo_mode}

  alias Marskal.Accounts
  alias Marskal.Devices

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      inspector={assigns[:inspector]}
      nav={assigns[:nav]}
      change_version={assigns[:change_version] || 0}
    >
      <div class="text-center">
        <.header>
          Account Settings
          <:subtitle>Manage your account email address and password settings</:subtitle>
        </.header>
      </div>

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_user_email"
          spellcheck="false"
          value={@current_email}
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label="New password"
          autocomplete="new-password"
          spellcheck="false"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          autocomplete="new-password"
          spellcheck="false"
        />
        <.button variant="primary" phx-disable-with="Saving...">
          Save Password
        </.button>
      </.form>

      <div class="divider" />

      <.form for={@preferences_form} id="preferences_form" phx-change="update_preferences">
        <.input
          field={@preferences_form[:week_start]}
          type="select"
          label="Week starts on"
          options={[{"Monday", 1}, {"Saturday", 6}, {"Sunday", 7}]}
        />
        <p>
          Repeats every few weeks keep the day they were made with.
        </p>
        <.input
          field={@preferences_form[:locale]}
          type="select"
          label="Dates and times"
          options={locale_options(@current_scope.user)}
        />
        <p>
          The order of day and month, and the clock, as in the region you pick.
        </p>
        <.input
          field={@preferences_form[:home_view]}
          type="select"
          label="After login"
          options={[
            {"Inbox", "inbox"},
            {"Open tasks", "open_tasks"},
            {"Agenda", "agenda"},
            {"Flagged", "flagged"}
          ]}
        />
        <p>
          This page opens when you log in.
        </p>
      </.form>

      <div class="divider" />

      <style :type={MarskalWeb.ColocatedCSS}>
        @scope (.device-list) {
          ul {
            list-style: none;
            margin: 0;
            padding: 0;
            display: flex;
            flex-direction: column;
            gap: 0.5rem;
          }

          li {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: var(--space);
            padding: 0.65rem 0.85rem;
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: var(--radius);
          }

          li div {
            display: flex;
            flex-direction: column;
          }

          .muted {
            color: var(--muted);
            font-size: 0.9rem;
          }
        }
      </style>

      <section id="devices" class="device-list">
        <h2>Devices</h2>
        <p class="muted">Programs signed in as you, such as the <code>marskal</code> command.</p>
        <p :if={@devices == []} class="empty">No devices are signed in.</p>
        <ul :if={@devices != []}>
          <li :for={device <- @devices} id={"device-#{device.id}"}>
            <div>
              <strong>{device.name}</strong>
              <span class="muted">{last_used(device, @current_scope.user)}</span>
            </div>
            <button
              class="btn"
              phx-click="sign_out_device"
              phx-value-id={device.id}
              data-confirm={"Sign out #{device.name}?"}
            >
              Sign out
            </button>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:preferences_form, preferences_form(Accounts.preferences(user)))
      |> assign(:trigger_submit, false)
      |> assign(:devices, Devices.list(user))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_preferences", %{"preferences" => params}, socket) do
    scope = socket.assigns.current_scope

    case Accounts.update_preferences(scope.user, params, Ecto.UUID.generate(version: 7)) do
      {:ok, preferences} ->
        Marskal.Cldr.put_locale(preferences.locale)

        {:noreply,
         socket
         |> assign(:current_scope, %{scope | user: %{scope.user | preferences: preferences}})
         |> assign(:preferences_form, preferences_form(preferences))
         |> put_flash(:info, "UserPreferences saved.")}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :preferences_form, to_form(changeset, as: :preferences, action: :update))}
    end
  end

  def handle_event("sign_out_device", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    _ = Devices.sign_out(user, id)
    {:noreply, assign(socket, :devices, Devices.list(user))}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  defp last_used(%{last_used_at: nil}, _user), do: "not used yet"

  defp last_used(device, user) do
    {date, _time} = Marskal.Dates.to_local(device.last_used_at, Accounts.timezone(user))
    "last used " <> Marskal.DateFormat.date(date, :day_month_year)
  end

  # Each region with now in its format, as an example.
  defp locale_options(user) do
    now = DateTime.shift_zone!(DateTime.utc_now(), Accounts.timezone(user))

    for {locale, region} <- Marskal.DateFormat.locales() do
      {"#{region}: #{Marskal.DateFormat.date_time(now, locale: locale)}", locale}
    end
  end

  defp preferences_form(preferences),
    do: preferences |> Accounts.change_preferences() |> to_form(as: :preferences)
end
