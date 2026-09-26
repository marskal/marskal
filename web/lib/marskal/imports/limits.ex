defmodule Marskal.Imports.Limits do
  @moduledoc false

  defstruct payload_bytes: 50 * 1024 * 1024,
            inflated_bytes: 150 * 1024 * 1024,
            entry_bytes: 40 * 1024 * 1024,
            xml_bytes: 20 * 1024 * 1024,
            zip_entries: 500,
            inner_zips: 150,
            records: 20_000,
            title_chars: 500,
            notes_chars: 32_768,
            imports_per_hour: 20,
            bundle_files: 200,
            read_chunk: 64 * 1024
end
