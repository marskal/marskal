defmodule Marskal.Imports.BundlePackager do
  @moduledoc """
  Zips a backup uploaded as a folder.

  A `.ofocus-backup` is a macOS package, so the import page's folder picker
  posts its files one by one with their relative paths. This packs them into
  the same zip a Finder-compressed backup would be, so the adapter only ever
  reads zips. Paths with `..` or a leading `/` are refused, and file counts
  and sizes are held to `Imports.Limits`. Failures raise `ArgumentError`
  with a message fit for the upload form.
  """

  alias Marskal.Imports.Limits

  def call(files, limits \\ %Limits{}) do
    if files == [], do: raise(ArgumentError, "No files in the OmniFocus backup.")

    if length(files) > limits.bundle_files,
      do: raise(ArgumentError, "Too many files in the backup.")

    entries =
      files
      |> Enum.map(fn {path, data} ->
        name = sanitize(path)
        if byte_size(data) > limits.entry_bytes, do: raise(ArgumentError, "Backup is too large.")
        {to_charlist(name), data}
      end)
      |> Enum.reject(fn {name, _} -> name == [] or List.last(name) == ?/ end)

    total = entries |> Enum.map(fn {_, data} -> byte_size(data) end) |> Enum.sum()
    if total > limits.payload_bytes, do: raise(ArgumentError, "Backup is too large.")

    case :zip.zip(~c"omnifocus.zip", entries, [:memory]) do
      {:ok, {_name, bin}} -> bin
      {:error, _} -> raise ArgumentError, "The backup zip could not be read."
    end
  end

  defp sanitize(path) do
    name = path |> to_string() |> String.replace("\\", "/")

    if String.contains?(name, "..") or String.starts_with?(name, "/") do
      raise ArgumentError, "Unsafe path in backup: #{path}"
    end

    name
  end
end
