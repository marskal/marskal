defmodule MarskalWeb.ImportBatchController do
  use MarskalWeb, :controller

  alias Marskal.Imports
  alias Marskal.Imports.Todoist

  def create(conn, params) do
    user = conn.assigns.current_scope.user
    payload = Map.get(params, "import_batch", %{})

    case Imports.ingest_upload(user, payload) do
      {:ok, batch} ->
        conn
        |> put_flash(:info, reading_flash(batch))
        |> redirect(to: ~p"/imports/#{batch.id}")

      {:error, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: upload_return(payload))
    end
  end

  defp reading_flash(%{source: "taskpaper"}), do: gettext("Reading the outline…")
  defp reading_flash(_batch), do: "Reading backup…"

  defp upload_return(%{"kind" => "taskpaper"}), do: ~p"/imports/taskpaper"
  defp upload_return(_payload), do: ~p"/imports/new"

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

  def todoist(conn, _params) do
    user = conn.assigns.current_scope.user

    cond do
      not Todoist.configured?() ->
        conn
        |> put_flash(:error, "Todoist sign-in is not configured.")
        |> redirect(to: ~p"/imports")

      Imports.rate_limited?(user) ->
        conn
        |> put_flash(:error, "Too many imports in the last hour. Try again later.")
        |> redirect(to: ~p"/imports")

      true ->
        state = Todoist.random_state()

        conn
        |> put_session(:todoist_oauth_state, state)
        |> redirect(external: Todoist.authorize_url(redirect_uri(conn), state))
    end
  end

  def todoist_callback(conn, params) do
    user = conn.assigns.current_scope.user
    expected = get_session(conn, :todoist_oauth_state)
    conn = delete_session(conn, :todoist_oauth_state)

    cond do
      params["error"] == "access_denied" ->
        conn
        |> put_flash(:error, "Todoist access was declined.")
        |> redirect(to: ~p"/imports")

      not valid_state?(params["state"], expected) ->
        conn
        |> put_flash(:error, "Todoist sign-in could not be confirmed. Try again.")
        |> redirect(to: ~p"/imports")

      true ->
        case Imports.ingest_todoist(user, params["code"], redirect_uri(conn)) do
          {:ok, batch} ->
            conn
            |> put_flash(:info, "Reading your Todoist account…")
            |> redirect(to: ~p"/imports/#{batch.id}")

          {:error, message} ->
            conn
            |> put_flash(:error, message)
            |> redirect(to: ~p"/imports")
        end
    end
  end

  defp redirect_uri(conn) do
    scheme = Atom.to_string(conn.scheme)
    port = conn.port

    origin =
      if port in [nil, URI.default_port(scheme)] do
        "#{scheme}://#{conn.host}"
      else
        "#{scheme}://#{conn.host}:#{port}"
      end

    Todoist.redirect_uri(origin)
  end

  defp valid_state?(given, expected) when is_binary(given) and is_binary(expected) do
    byte_size(given) == byte_size(expected) and Plug.Crypto.secure_compare(given, expected)
  end

  defp valid_state?(_given, _expected), do: false
end
