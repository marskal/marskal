# frozen_string_literal: true

module Imports
  module Limits
    PAYLOAD_BYTES = 50.megabytes
    INFLATED_BYTES = 150.megabytes
    ENTRY_BYTES = 40.megabytes
    XML_BYTES = 20.megabytes
    ZIP_ENTRIES = 500
    INNER_ZIPS = 150
    RECORDS = 20_000
    TITLE_CHARS = 500
    NOTES_CHARS = 32_768
    IMPORTS_PER_HOUR = 20
    BUNDLE_FILES = 200
    READ_CHUNK = 64.kilobytes
  end
end
