defmodule MarskalWeb.Router do
  use MarskalWeb, :router

  import MarskalWeb.UserAuth
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MarskalWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MarskalWeb do
    pipe_through :browser

    get "/up", HealthController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", MarskalWeb do
  #   pipe_through :api
  # end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:marskal, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  scope "/dev" do
    pipe_through [:browser, :require_authenticated_user, :require_superuser]

    live_dashboard "/dashboard", metrics: MarskalWeb.Telemetry
  end

  ## Authentication routes

  scope "/", MarskalWeb do
    pipe_through [:browser, :require_authenticated_user]

    post "/imports", ImportBatchController, :create
    post "/imports/:id/apply", ImportBatchController, :apply

    live_session :require_authenticated_user,
      on_mount: [{MarskalWeb.UserAuth, :require_authenticated}] do
      live "/", OpenTasksLive, :index
      live "/imports", ImportLive, :index
      live "/imports/new", ImportLive, :new
      live "/imports/:id", ImportLive, :show
      live "/inbox", InboxLive, :index
      live "/projects/:id", ProjectLive, :show
      live "/folders/:id", FolderLive, :show
      live "/tasks/:id", TaskLive, :show
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", MarskalWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{MarskalWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
