defmodule Marskal.Imports.ExpireJobTest do
  use Marskal.DataCase, async: true
  use Oban.Testing, repo: Marskal.Repo

  alias Marskal.AccountsFixtures
  alias Marskal.ImportBatch
  alias Marskal.Imports
  alias Marskal.Imports.ExpireJob

  setup do
    %{user: AccountsFixtures.user_fixture()}
  end

  test "an upload left unapplied for a day loses its payload", %{user: user} do
    stale = batch!(user, :previewed, hours_ago: 25)
    pending = batch!(user, :pending, hours_ago: 25)
    fresh = batch!(user, :previewed, hours_ago: 1)
    applied = batch!(user, :applied, hours_ago: 48)

    assert {2, _} = ExpireJob.expire(DateTime.utc_now(:second))

    for batch <- [stale, pending] do
      batch = reload(batch)
      assert batch.status == :expired
      assert batch.payload == nil
      assert batch.error_message =~ "expired"
    end

    assert reload(fresh).status == :previewed
    assert reload(fresh).payload
    assert reload(applied).status == :applied
    assert {:error, :not_ready} = Imports.enqueue_apply(reload(stale))
  end

  test "the job runs", %{user: user} do
    stale = batch!(user, :previewed, hours_ago: 25)
    assert :ok = perform_job(ExpireJob, %{})
    assert reload(stale).status == :expired
  end

  defp batch!(user, status, hours_ago: hours) do
    at = DateTime.add(DateTime.utc_now(:second), -hours, :hour)

    %ImportBatch{}
    |> ImportBatch.changeset(%{
      user_id: user.id,
      source: "omnifocus",
      channel: :file,
      status: status,
      filename: "OmniFocus.ofocus-backup",
      payload: "zip"
    })
    |> Ecto.Changeset.force_change(:inserted_at, at)
    |> Ecto.Changeset.force_change(:updated_at, at)
    |> Repo.insert!()
  end

  defp reload(batch), do: Imports.load_payload(Repo.get!(ImportBatch, batch.id))
end
