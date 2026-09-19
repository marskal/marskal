# frozen_string_literal: true

require "zip"

module Imports
  class BundlePackager
    def self.call(files:, paths:)
      new(files: files, paths: paths).call
    end

    def initialize(files:, paths:)
      @pairs = Array(files).zip(Array(paths))
    end

    def call
      raise ArgumentError, "No files in the OmniFocus backup." if @pairs.empty?
      raise ArgumentError, "Too many files in the backup." if @pairs.size > Limits::BUNDLE_FILES

      total = 0
      buffer = Zip::OutputStream.write_buffer do |zip|
        @pairs.each do |file, path|
          next if file.blank?

          name = sanitize(path.presence || file.original_filename)
          next if name.blank? || name.end_with?("/")

          data = file.read
          total += data.bytesize
          if data.bytesize > Limits::ENTRY_BYTES || total > Limits::PAYLOAD_BYTES
            raise ArgumentError, "Backup is too large."
          end

          zip.put_next_entry(name)
          zip.write(data)
        end
      end
      buffer.rewind
      buffer
    end

    private
      def sanitize(path)
        name = path.to_s.tr("\\", "/")
        raise ArgumentError, "Unsafe path in backup: #{path}" if name.include?("..") || name.start_with?("/")

        name
      end
  end
end
