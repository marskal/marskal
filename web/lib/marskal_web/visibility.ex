defmodule MarskalWeb.Visibility do
  @moduledoc """
  Which resolved and deferred rows this browser shows.

  The choice is Done, Dropped, and Deferred, any combination, defaulting to
  none of them. It is this browser's: a cookie for the next full load, and
  `localStorage` so a reload before that cookie lands still agrees. Live
  navigation does not re-read the cookie, so the latest value is also kept
  in ETS under a key in the session. It is not a user preference and it is
  not synced (ADR 0023).
  """

  import Plug.Conn

  @behaviour Plug

  @cookie "marskal_visibility"
  @table :marskal_visibility
  @kinds [:done, :dropped, :deferred]
  @max_age 60 * 60 * 24 * 365

  defstruct done: false, dropped: false, deferred: false

  def init(opts), do: opts

  @doc """
  Reads the choice onto the session. A cookie present on the request wins.
  With no cookie, the value already stored for this session stands, and a
  first visit shows none of them.
  """
  def call(conn, _opts) do
    key = get_session(conn, "visibility_key") || new_key()

    value =
      case conn.cookies[@cookie] do
        nil -> fetch(key) || none()
        raw -> parse(raw)
      end

    store(key, value)

    conn
    |> put_session("visibility_key", key)
    |> put_session("visibility", encode(value))
  end

  def cookie, do: @cookie

  def cookie_opts do
    [path: "/", max_age: @max_age, same_site: "Lax", http_only: true]
  end

  def new_key, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

  def none, do: %__MODULE__{}
  def all, do: %__MODULE__{done: true, dropped: true, deferred: true}

  def none?(%__MODULE__{done: false, dropped: false, deferred: false}), do: true
  def none?(%__MODULE__{}), do: false
  def all?(%__MODULE__{done: true, dropped: true, deferred: true}), do: true
  def all?(%__MODULE__{}), do: false

  @doc "The kinds this choice shows, in a stable order."
  def kinds(%__MODULE__{} = value), do: Enum.filter(@kinds, &Map.get(value, &1))

  @doc "The session key's choice, or the encoded session value after a restart."
  def from_mount(_socket, session) when is_map(session) do
    case session["visibility_key"] do
      key when is_binary(key) ->
        value = fetch(key) || parse(session["visibility"] || "")
        {key, store(key, value)}

      _ ->
        key = new_key()
        {key, store(key, none())}
    end
  end

  @doc "Applies a toolbar event, or a value stored in this browser."
  def change(%__MODULE__{}, %{"set" => "all"}), do: all()
  def change(%__MODULE__{}, %{"set" => "none"}), do: none()

  def change(%__MODULE__{} = current, %{"kind" => kind}) when kind in ~w(done dropped deferred) do
    Map.update!(current, String.to_existing_atom(kind), &(!&1))
  end

  def change(%__MODULE__{}, %{"stored" => stored}) when is_binary(stored), do: parse(stored)
  def change(%__MODULE__{} = current, _params), do: current

  def parse(raw) when is_binary(raw) do
    chosen =
      raw
      |> String.split(",", trim: true)
      |> MapSet.new(&String.trim/1)

    %__MODULE__{
      done: MapSet.member?(chosen, "done"),
      dropped: MapSet.member?(chosen, "dropped"),
      deferred: MapSet.member?(chosen, "deferred")
    }
  end

  def parse(_raw), do: none()

  def encode(%__MODULE__{} = value) do
    value
    |> kinds()
    |> Enum.map_join(",", &Atom.to_string/1)
  end

  def fetch(key) when is_binary(key) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, %__MODULE__{} = value}] -> value
      [] -> nil
    end
  end

  def store(key, %__MODULE__{} = value) when is_binary(key) do
    ensure_table()
    :ets.insert(@table, {key, value})
    value
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
        rescue
          ArgumentError -> @table
        end

      tid ->
        tid
    end
  end
end
