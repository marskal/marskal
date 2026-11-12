defmodule MarskalWeb.UserLive.Settings do
  @moduledoc """
  What to call the user, and how the app behaves for them (ADR 0023). Email, password, and
  devices are on `MarskalWeb.UserLive.Security`, behind a recent login.
  """
  use MarskalWeb, :live_view

  alias Marskal.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      inspector={assigns[:inspector]}
      nav={assigns[:nav]}
      change_version={assigns[:change_version] || 0}
      visibility={assigns[:visibility]}
    >
      <MarskalWeb.SettingsComponents.page current={:preferences}>
        <section id="profile">
          <h2>{gettext("You")}</h2>
          <.form for={@name_form} id="name_form" phx-submit="update_name">
            <.input
              field={@name_form[:name]}
              type="text"
              label={gettext("Name")}
              autocomplete="name"
              maxlength="100"
            />
            <p class="hint">
              {gettext(
                "What to call you. Its initials mark you in the header; without a name, an icon does."
              )}
            </p>
            <div class="actions">
              <.button variant="primary" phx-disable-with={gettext("Saving...")}>
                {gettext("Save name")}
              </.button>
            </div>
          </.form>
        </section>
        <.form for={@preferences_form} id="preferences_form" phx-change="update_preferences">
          <section id="preferences-dates">
            <h2>{gettext("Calendar")}</h2>
            <.input
              field={@preferences_form[:week_start]}
              type="select"
              label={gettext("Week starts on")}
              options={[{gettext("Monday"), 1}, {gettext("Saturday"), 6}, {gettext("Sunday"), 7}]}
            />
            <p class="hint">
              {gettext("Repeats every few weeks keep the day they were made with.")}
            </p>
            <.input
              field={@preferences_form[:locale]}
              type="select"
              label={gettext("Dates and times")}
              options={locale_options(@current_scope.user)}
            />
            <p class="hint">
              {gettext("The order of day and month, and the clock, as in the region you pick.")}
            </p>
          </section>
          <section id="preferences-navigation">
            <h2>{gettext("Navigation")}</h2>
            <.input
              field={@preferences_form[:home_view]}
              type="select"
              label={gettext("Home view")}
              options={[
                {gettext("Inbox"), "inbox"},
                {gettext("Open tasks"), "open_tasks"},
                {gettext("Agenda"), "agenda"},
                {gettext("Flagged"), "flagged"}
              ]}
            />
            <p class="hint">
              {gettext("Select what view is “Home” – where you land when logging in.")}
            </p>
            <.input
              field={@preferences_form[:keymap]}
              type="select"
              label={gettext("Keymap")}
              options={[
                {gettext("Standard"), "standard"},
                {gettext("Vim-style"), "vim"}
              ]}
            />
            <p class="hint">
              {gettext(
                "Standard uses the arrow keys, Space to complete, Delete to drop, f to flag, and n for a new task. Vim-style adds j, k, x, dd, and others. Press ? on any page for the full list."
              )}
            </p>
          </section>
        </.form>
      </MarskalWeb.SettingsComponents.page>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, gettext("Settings"))
     |> assign(:preferences_form, preferences_form(Accounts.preferences(user)))
     |> assign(:name_form, to_form(Accounts.change_user_name(user)))}
  end

  @impl true
  def handle_event("update_name", %{"user" => params}, socket) do
    scope = socket.assigns.current_scope

    case Accounts.update_user_name(scope.user, Map.take(params, ["name"])) do
      {:ok, user} ->
        user = %{scope.user | name: user.name}

        {:noreply,
         socket
         |> assign(:current_scope, %{scope | user: user})
         |> assign(:name_form, to_form(Accounts.change_user_name(user)))
         |> put_flash(:info, gettext("Name saved."))}

      {:error, changeset} ->
        {:noreply, assign(socket, :name_form, to_form(changeset, action: :update))}
    end
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
         |> put_flash(:info, gettext("Preferences saved."))}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :preferences_form, to_form(changeset, as: :preferences, action: :update))}
    end
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
