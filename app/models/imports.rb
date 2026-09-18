# frozen_string_literal: true

module Imports
  def self.adapters
    [ OmnifocusAdapter ]
  end

  def self.adapter_for(io, filename:)
    adapters.find { |adapter| adapter.match?(io, filename: filename) }
  end
end
