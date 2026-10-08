defmodule Marskal.Recurrence.GenerateJob do
  @moduledoc """
  Creates the next occurrence of each regular series whose latest slot has
  passed (`Marskal.Recurrence.generate/1`). Runs each minute from Oban's
  cron.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 60]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Marskal.Recurrence.generate()
    :ok
  end
end
