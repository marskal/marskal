defmodule Marskal.Imports do
  @moduledoc """
  Upload an OmniFocus backup, preview it, and apply it.

  Parsing and applying run on the Oban `imports` queue. The upload request
  only stores the file and enqueues the job.
  """

  import Ecto.Query
  alias Marskal.Accounts.User
  alias Marskal.ImportBatch
  alias Marskal.Imports.ApplyJob
  alias Marskal.Imports.BundlePackager
  alias Marskal.Imports.Limits
  alias Marskal.Imports.ParseJob
  alias Marskal.Repo

  def list_batches(%User{} = user) do
    ImportBatch
    |> where([b], b.user_id == ^user.id)
    |> order_by([b], desc: b.inserted_at, desc: b.id)
    |> Repo.all()
  end

  def get_batch(%User{} = user, id) when is_binary(id) do
    Repo.get_owned(ImportBatch, user, id)
  end

  @doc "The payload is not loaded by default. The jobs read it here."
  def load_payload(%ImportBatch{payload: nil, id: id} = batch) do
    payload = Repo.one(from b in ImportBatch, where: b.id == ^id, select: b.payload)
    %{batch | payload: payload}
  end

  def load_payload(%ImportBatch{} = batch), do: batch

  def rate_limited?(%User{} = user) do
    hour_ago = DateTime.add(DateTime.utc_now(:second), -3600, :second)
    limit = %Limits{}.imports_per_hour

    count =
      ImportBatch
      |> where([b], b.user_id == ^user.id and b.inserted_at > ^hour_ago)
      |> Repo.aggregate(:count)

    count >= limit
  end

  def ingest_upload(%User{} = user, params) when is_map(params) do
    cond do
      rate_limited?(user) ->
        {:error, "Too many imports in the last hour. Try again later."}

      true ->
        case read_payload(params) do
          {:ok, filename, bytes} -> insert_and_enqueue(user, filename, bytes)
          {:error, message} -> {:error, message}
        end
    end
  end

  def enqueue_apply(%ImportBatch{status: :previewed} = batch) do
    result =
      Ecto.Multi.new()
      |> Ecto.Multi.update(
        :batch,
        Ecto.Changeset.change(batch, %{status: :applying, error_message: nil})
      )
      |> Oban.insert(:job, fn %{batch: batch} -> ApplyJob.new(%{batch_id: batch.id}) end)
      |> Repo.transaction()

    case result do
      {:ok, %{batch: batch}} -> {:ok, batch}
      {:error, :batch, _changeset, _} -> {:error, :not_ready}
    end
  end

  def enqueue_apply(%ImportBatch{}), do: {:error, :not_ready}

  defp insert_and_enqueue(user, filename, bytes) do
    changeset =
      ImportBatch.changeset(%ImportBatch{}, %{
        user_id: user.id,
        source: "omnifocus",
        channel: :file,
        status: :pending,
        filename: filename,
        payload: bytes
      })

    result =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:batch, changeset)
      |> Oban.insert(:job, fn %{batch: batch} -> ParseJob.new(%{batch_id: batch.id}) end)
      |> Repo.transaction()

    case result do
      {:ok, %{batch: batch}} -> {:ok, batch}
      {:error, :batch, changeset, _} -> {:error, error_text(changeset)}
    end
  end

  defp read_payload(%{"payload" => %Plug.Upload{} = upload}) do
    {:ok, safe_filename(upload.filename), File.read!(upload.path)}
  rescue
    error in File.Error -> {:error, Exception.message(error)}
  end

  defp read_payload(%{"bundle_files" => files} = params) when files not in [nil, "", []] do
    files = List.wrap(files)

    entries =
      Enum.with_index(files, fn
        %Plug.Upload{} = file, index ->
          path =
            params |> Map.get("bundle_paths") |> List.wrap() |> Enum.at(index) || file.filename

          {path, File.read!(file.path)}

        _other, _index ->
          nil
      end)

    if Enum.any?(entries, &is_nil/1) do
      {:error, "Choose an OmniFocus backup to upload."}
    else
      {:ok, "OmniFocus.ofocus-backup.zip", BundlePackager.call(entries)}
    end
  rescue
    error in [ArgumentError, File.Error] -> {:error, Exception.message(error)}
  end

  defp read_payload(_params), do: {:error, "Choose an OmniFocus backup to upload."}

  defp safe_filename(name) do
    base = name |> to_string() |> Path.basename() |> String.trim()
    base = if base == "", do: "OmniFocus.ofocus-backup", else: base
    String.slice(base, 0, 255)
  end

  defp error_text(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> List.first() ||
      "Could not save this import."
  end
end
