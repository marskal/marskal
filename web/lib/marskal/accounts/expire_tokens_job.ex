defmodule Marskal.Accounts.ExpireTokensJob do
  @moduledoc """
  Deletes session and email tokens past their validity
  (`Marskal.Accounts.delete_expired_tokens/1`). Runs daily from Oban's cron.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {_count, _} = Marskal.Accounts.delete_expired_tokens()
    :ok
  end
end
