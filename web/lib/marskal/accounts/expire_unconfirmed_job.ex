defmodule Marskal.Accounts.ExpireUnconfirmedJob do
  @moduledoc """
  Deletes accounts nobody confirmed while their link lasted, so a squatted
  address comes free (`Marskal.Accounts.delete_unconfirmed_users/1`). Runs
  daily from Oban's cron.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {_count, _} = Marskal.Accounts.delete_unconfirmed_users()
    :ok
  end
end
