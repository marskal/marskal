defmodule Marskal.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MarskalWeb.Telemetry,
      Marskal.Repo,
      {Oban, Application.fetch_env!(:marskal, Oban)},
      {DNSCluster, query: Application.get_env(:marskal, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Marskal.PubSub},
      # Start a worker by calling: Marskal.Worker.start_link(arg)
      # {Marskal.Worker, arg},
      # Start to serve requests, typically the last entry
      MarskalWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Marskal.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MarskalWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
