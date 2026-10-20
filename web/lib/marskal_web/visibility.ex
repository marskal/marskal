defmodule MarskalWeb.Visibility do
  @moduledoc """
  Which resolved and deferred rows this browser shows.

  The choice is a list of `:done`, `:dropped`, and `:deferred`, in that
  order, defaulting to none of them; it is what the contexts take as
  `show:`. It is this browser's, not a user preference, and not synced
  (ADR 0023).

  One cookie holds it. The page's hook writes the cookie, the dead render
  reads it through the live session (`session/1`), and every live mount
  gets it again as a connect param, so a page reached by live navigation
  after a change agrees with it.
  """

  @cookie "marskal_show"
  @kinds [:done, :dropped, :deferred]

  def cookie, do: @cookie
  def kinds, do: @kinds

  @doc "The live session's share of the request: the cookie as it came."
  def session(conn), do: %{"show" => conn.cookies[@cookie] || ""}

  @doc "The choice on mount: the connect param when connected, else the session's."
  def from_mount(socket, session) do
    case Phoenix.LiveView.get_connect_params(socket) do
      %{"show" => raw} -> parse(raw)
      _ -> parse(session["show"])
    end
  end

  @doc "Shows `kind` if hidden, hides it if shown."
  def toggle(show, kind) when kind in @kinds do
    if kind in show,
      do: List.delete(show, kind),
      else: Enum.filter(@kinds, &(&1 == kind or &1 in show))
  end

  def parse(raw) when is_binary(raw) do
    chosen = raw |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    Enum.filter(@kinds, &(Atom.to_string(&1) in chosen))
  end

  def parse(_raw), do: []

  def encode(show) when is_list(show), do: Enum.join(show, ",")
end
