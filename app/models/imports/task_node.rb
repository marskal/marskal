# frozen_string_literal: true

module Imports
  TaskNode = Data.define(:source_id, :title, :notes, :inbox, :project_source_id, :parent_source_id, :state, :extras)
end
