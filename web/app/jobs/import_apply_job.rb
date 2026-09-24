# frozen_string_literal: true

class ImportApplyJob < ApplicationJob
  queue_as :default

  def perform(import_batch)
    Imports::Applier.call(import_batch)
  end
end
