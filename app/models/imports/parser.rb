# frozen_string_literal: true

require "zip"

module Imports
  class Parser
    def self.call(batch)
      new(batch).call
    end

    def initialize(batch)
      @batch = batch
    end

    def call
      io = StringIO.new(@batch.payload.download)
      adapter = Imports.adapter_for(io, filename: @batch.filename)
      unless adapter
        fail_batch!("This file is not a supported backup. Export an OmniFocus Backup Document (.ofocus-backup).")
        return
      end

      @batch.source = adapter.key
      graph = adapter.parse(io, filename: @batch.filename)
      @batch.update!(
        source: graph.source,
        status: :previewed,
        stats: graph.stats,
        error_message: nil
      )
    rescue ArgumentError => e
      fail_batch!(e.message)
    rescue Zip::Error
      fail_batch!("The backup zip could not be read.")
    rescue StandardError => e
      fail_batch!("Could not read this backup (#{e.class}).")
      raise if Rails.env.local? && ENV["IMPORT_RAISE"]
    end

    private
      def fail_batch!(message)
        @batch.update!(status: :failed, error_message: message)
      end
  end
end
