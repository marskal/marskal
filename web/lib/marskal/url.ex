defmodule Marskal.Url do
  @moduledoc """
  The optional URL on a task or project (ADR 0022): absolute, any scheme
  but the ones that run in the page, at most 2048 characters.
  """

  import Ecto.Changeset

  @max 2048
  @refused ~w(javascript data vbscript)
  @shape ~r/\A([A-Za-z][A-Za-z0-9+.\-]*):\S+\z/u

  def max, do: @max

  @doc "Trims the cast `:url`, clears it when blank, and checks it."
  def validate(changeset, table) do
    changeset
    |> update_change(:url, &trim/1)
    |> validate_length(:url, max: @max)
    |> validate_change(:url, fn :url, url ->
      cond do
        not Regex.match?(@shape, url) -> [url: "must be a full URL, like https://example.com"]
        not safe?(url) -> [url: "cannot use that scheme"]
        true -> []
      end
    end)
    |> check_constraint(:url, name: :"#{table}_url_absolute", message: "must be a full URL")
  end

  defp trim(nil), do: nil

  defp trim(url) do
    case String.trim(url) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc "Whether `url` may be a link's `href`."
  def safe?(url) when is_binary(url) do
    case Regex.run(@shape, url) do
      [_, scheme] -> String.downcase(scheme) not in @refused
      nil -> false
    end
  end

  def safe?(_url), do: false
end
