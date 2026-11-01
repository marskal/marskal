defmodule MarskalWeb.Router do
  use MarskalWeb, :router

  import MarskalWeb.UserAuth
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug MarskalWeb.SecurityHeaders
    plug MarskalWeb.FetchMetadata
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MarskalWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug MarskalWeb.SecurityHeaders
  end

  # No session: a monitor would otherwise collect a cookie on every check.
  # `devenv up` probes this path too.
  pipeline :health do
    plug MarskalWeb.SecurityHeaders
  end

  scope "/", MarskalWeb do
    pipe_through :health

    get "/up", HealthController, :show
  end

  pipeline :api_auth do
    plug :accepts, ["json"]
    plug MarskalWeb.SecurityHeaders
    plug MarskalWeb.APIAuth
  end

  # The event stream answers text/event-stream, not JSON (ADR 0030).
  pipeline :api_events do
    plug MarskalWeb.SecurityHeaders
    plug MarskalWeb.APIAuth
  end

  scope "/api/v1", MarskalWeb do
    pipe_through :api_auth

    get "/sync/pull", SyncController, :pull
    post "/sync/push", SyncController, :push
  end

  scope "/api/v1", MarskalWeb do
    pipe_through :api_events

    get "/sync/events", SyncController, :events
  end

  # Hydra serves the OAuth metadata, the web app the resource's (ADR 0021).
  scope "/", MarskalWeb do
    pipe_through :api

    get "/.well-known/oauth-authorization-server", OAuthController, :metadata
    get "/.well-known/oauth-protected-resource", OAuthController, :resource_metadata
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:marskal, :dev_routes) do
    scope "/dev" do
      # Without SecurityHeaders: it frames each message and inlines its styles.
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  scope "/dev" do
    pipe_through [:browser, :require_authenticated_user, :require_superuser]

    live_dashboard "/dashboard", metrics: MarskalWeb.Telemetry, csp_nonce_assign_key: :csp_nonce
  end

  ## Authentication routes

  scope "/", MarskalWeb do
    pipe_through [:browser, :require_authenticated_user]

    # Hydra's login endpoint (ADR 0021).
    get "/oauth/login", OAuthController, :login

    post "/imports", ImportBatchController, :create
    get "/imports/todoist", ImportBatchController, :todoist
    get "/imports/todoist/callback", ImportBatchController, :todoist_callback
    post "/imports/:id/apply", ImportBatchController, :apply
    get "/tasks/:id", TaskController, :show
    get "/", PageController, :home

    live_session :require_authenticated_user,
      session: {MarskalWeb.Visibility, :session, []},
      on_mount: [
        {MarskalWeb.UserAuth, :require_authenticated},
        {MarskalWeb.Inspector, :default},
        {MarskalWeb.StaticChanged, :default}
      ] do
      live "/open", OpenTasksLive, :index
      live "/imports", ImportLive, :index
      live "/imports/new", ImportLive, :new
      live "/imports/:id", ImportLive, :show
      live "/inbox", InboxLive, :index
      live "/agenda", AgendaLive, :index
      live "/flagged", OpenTasksLive, :flagged
      live "/projects/:id", ProjectLive, :show
      live "/folders/:id", FolderLive, :show
      live "/tags/untagged", UntaggedLive, :index
      live "/tags/:id", TagLive, :show
      live "/device", DeviceLive, :verify
      live "/device/done", DeviceLive, :done
      live "/oauth/error", DeviceLive, :error
      live "/oauth/consent", ConsentLive, :show
      live "/users/settings", UserLive.Settings, :edit
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  # Pages that need a recent login. They are a live session of their own,
  # so reaching one is always a request the plug sees, and the login page
  # can send the user back.
  scope "/", MarskalWeb do
    pipe_through [:browser, :require_authenticated_user, :require_sudo_mode]

    live_session :require_sudo_mode,
      session: {MarskalWeb.Visibility, :session, []},
      on_mount: [
        {MarskalWeb.UserAuth, :require_authenticated},
        {MarskalWeb.Inspector, :default},
        {MarskalWeb.StaticChanged, :default}
      ] do
      live "/users/settings/security", UserLive.Security, :edit
      live "/users/settings/confirm-email/:token", UserLive.Security, :confirm_email
    end
  end

  scope "/", MarskalWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [
        {MarskalWeb.UserAuth, :mount_current_scope},
        {MarskalWeb.StaticChanged, :default}
      ] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/check-email", UserLive.CheckEmail, :show
      live "/users/confirm/:token", UserLive.Confirmation, :new
      live "/users/reset-password", UserLive.ForgotPassword, :new
      live "/users/reset-password/:token", UserLive.ResetPassword, :edit
    end

    get "/.well-known/change-password", PageController, :change_password
    post "/users/log-in", UserSessionController, :create
    post "/users/confirm", UserSessionController, :confirm
    delete "/users/log-out", UserSessionController, :delete
  end
end
