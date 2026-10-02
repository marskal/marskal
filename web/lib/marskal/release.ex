defmodule Marskal.Release do
  @moduledoc """
  Tasks run from the release, where Mix is not available.

      bin/marskal eval "Marskal.Release.migrate()"
      bin/marskal eval "Marskal.Release.ensure_oauth_clients()"
  """
  @app :marskal

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Creates or updates the OAuth clients in Hydra (ADR 0021). Hydra may
  still be starting, so this waits up to a minute.
  """
  def ensure_oauth_clients(attempts \\ 30) do
    load_app()
    {:ok, _} = Application.ensure_all_started(:req)

    case Marskal.Hydra.ensure_clients() do
      :ok ->
        :ok

      {:error, reason} when attempts > 1 ->
        IO.puts("Waiting for Hydra: #{inspect(reason)}")
        Process.sleep(2_000)
        ensure_oauth_clients(attempts - 1)

      {:error, reason} ->
        raise "Hydra did not take the OAuth clients: #{inspect(reason)}"
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
