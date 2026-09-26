defmodule MarskalWeb.ImportBatchController do
  use MarskalWeb, :controller

  alias Marskal.Imports

  def create(conn, params) do
    user = conn.assigns.current_scope.user
    payload = Map.get(params, "import_batch", %{})

    case Imports.ingest_upload(user, payload) do
      {:ok, batch} ->
        conn
        |> put_flash(:info, "Reading backup…")
        |> redirect(to: ~p"/imports/#{batch.id}")

      {:error, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: ~p"/imports/new")
    end
  end

  def apply(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    case Imports.get_batch(user, id) do
      nil ->
        conn
        |> put_flash(:error, "That import is not available.")
        |> redirect(to: ~p"/imports")

      batch ->
        case Imports.enqueue_apply(batch) do
          {:ok, batch} ->
            conn
            |> put_flash(:info, "Importing…")
            |> redirect(to: ~p"/imports/#{batch.id}")

          {:error, :not_ready} ->
            conn
            |> put_flash(:error, "This import is not ready to apply.")
            |> redirect(to: ~p"/imports/#{batch.id}")
        end
    end
  end
end
