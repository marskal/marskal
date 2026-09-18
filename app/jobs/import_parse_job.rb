# frozen_string_literal: true

class ImportParseJob < ApplicationJob
  queue_as :default

  def perform(import_batch)
    Imports::Parser.call(import_batch)
  end
end
