defmodule Marskal.Devices do
  @moduledoc """
  Devices signed in through Hydra (ADR 0021). Approving a device records it
  here; its access tokens carry its id. The sync API refuses a token whose
  device is gone, so signing out holds even before Hydra is told.
  """

  import Ecto.Query
  require Logger

  alias Marskal.Accounts.User
  alias Marskal.Devices.Device
  alias Marskal.Hydra
  alias Marskal.Repo

  # How stale last_used_at may get before a request writes it again.
  @touch_after_seconds 300

  def list(%User{} = user) do
    Device
    |> where([d], d.user_id == ^user.id)
    |> order_by([d], desc_nulls_last: d.last_used_at, desc: d.inserted_at)
    |> Repo.all()
  end

  def get(%User{} = user, id), do: Repo.get_owned(Device, user, id)

  def create(%User{} = user, attrs) do
    %Device{}
    |> Device.create_changeset(user, attrs)
    |> Repo.insert()
  end

  @doc "Removes a device that never got its consent, after Hydra refused it."
  def discard_unconsented(%Device{} = device), do: Repo.delete(device)

  @doc "Signs one device out: here first, then its consent in Hydra."
  def sign_out(%User{} = user, id) do
    case get(user, id) do
      nil ->
        {:error, :not_found}

      device ->
        {:ok, device} = Repo.delete(device)
        revoke(fn -> Hydra.revoke_consent(device.consent_request_id) end)
        {:ok, device}
    end
  end

  @doc "Signs every device of the user out, as a password change does."
  def sign_out_all(%User{} = user) do
    case Repo.delete_all(from d in Device, where: d.user_id == ^user.id) do
      {0, _} -> :ok
      {_count, _} -> revoke(fn -> Hydra.revoke_subject(user.id) end)
    end
  end

  @doc """
  The user and device behind a token Hydra says is live, for the sync API.
  Returns `{:ok, user, device, scopes}` or `:error`.
  """
  def authenticate(token, now \\ DateTime.utc_now(:second)) do
    with {:ok, %{"active" => true, "token_use" => "access_token"} = info} <-
           Hydra.introspect(token),
         %{"sub" => user_id, "ext" => %{"device_id" => device_id}} <- info,
         {:ok, device_id} <- Ecto.UUID.cast(device_id),
         %Device{} = device <- Repo.get_by(Device, id: device_id, user_id: user_id) do
      device = Repo.preload(device, :user) |> touch(now)
      {:ok, device.user, device, String.split(info["scope"] || "")}
    else
      _ -> :error
    end
  end

  defp touch(%Device{last_used_at: last} = device, now) do
    if is_nil(last) or DateTime.diff(now, last) > @touch_after_seconds do
      {1, _} =
        Repo.update_all(from(d in Device, where: d.id == ^device.id), set: [last_used_at: now])

      %{device | last_used_at: now}
    else
      device
    end
  end

  # The row is already gone, so the sync API refuses the device whatever
  # Hydra says. A failure here leaves tokens Hydra still honours, and only
  # Hydra's own endpoints accept them.
  defp revoke(fun) do
    case fun.() do
      :ok -> :ok
      {:error, reason} -> Logger.warning("Hydra did not revoke consent: #{inspect(reason)}")
    end
  end
end
