# frozen_string_literal: true

require "zip"

module Imports
  class BundlePackager
    MAX_FILES = 200

    def self.call(files:, paths:)
      new(files: files, paths: paths).call
    end

    def initialize(files:, paths:)
      @pairs = Array(files).zip(Array(paths))
    end

    def call
      raise ArgumentError, "No files in the OmniFocus backup." if @pairs.empty?
      raise ArgumentError, "Too many files in the backup." if @pairs.size > MAX_FILES

      buffer = Zip::OutputStream.write_buffer do |zip|
        @pairs.each do |file, path|
          next if file.blank?

          name = sanitize(path.presence || file.original_filename)
          next if name.blank? || name.end_with?("/")

          zip.put_next_entry(name)
          zip.write(file.read)
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
