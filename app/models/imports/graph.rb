# frozen_string_literal: true

module Imports
  Graph = Data.define(:source, :folders, :projects, :tasks) do
    def stats
      {
        "folders" => folders.size,
        "projects" => projects.size,
        "tasks" => tasks.size,
        "inbox" => tasks.count(&:inbox),
        "samples" => samples
      }
    end

    def samples
      (projects.map(&:title) + tasks.map(&:title)).compact.reject(&:blank?).first(8)
    end
  end
end
