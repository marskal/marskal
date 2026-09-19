# frozen_string_literal: true

module Imports
  class Applier
    def self.call(batch)
      new(batch).call
    end

    def initialize(batch)
      @batch = batch
      @user = batch.user
    end

    def call
      io = StringIO.new(@batch.payload.download)
      adapter = Imports.adapter_for(io, filename: @batch.filename)
      raise ArgumentError, "Unknown backup format" unless adapter

      graph = adapter.parse(io, filename: @batch.filename)
      created = { "folders" => 0, "projects" => 0, "tasks" => 0 }
      skipped = { "folders" => 0, "projects" => 0, "tasks" => 0 }

      ApplicationRecord.transaction do
        folder_ids = apply_folders(graph.folders, created, skipped)
        project_ids = apply_projects(graph.projects, folder_ids, created, skipped)
        apply_tasks(graph.tasks, project_ids, created, skipped)
        @batch.update!(
          status: :applied,
          stats: @batch.stats.merge("created" => created, "skipped" => skipped),
          error_message: nil
        )
      end
    rescue StandardError => e
      @batch.update!(status: :failed, error_message: "Import failed: #{e.message}")
      raise if Rails.env.local? && ENV["IMPORT_RAISE"]
    end

    private
      def existing
        @existing ||= @user.import_items.where(source: @batch.source).index_by(&:source_id)
      end

      def apply_folders(folders, created, skipped)
        ids = {}
        remaining = folders.index_by(&:source_id)
        guard = remaining.size + 1
        until remaining.empty? || guard <= 0
          guard -= 1
          remaining.keys.each do |sid|
            node = remaining[sid]
            next if node.parent_source_id.present? && !ids.key?(node.parent_source_id) && remaining.key?(node.parent_source_id)

            ids[sid] = upsert_folder(node, ids, created, skipped)
            remaining.delete(sid)
          end
        end
        remaining.each_value { |node| ids[node.source_id] = upsert_folder(node, ids, created, skipped) }
        ids
      end

      def upsert_folder(node, folder_ids, created, skipped)
        if (item = existing[node.source_id])
          skipped["folders"] += 1
          return item.project_folder_id
        end

        folder = @user.project_folders.create!(
          name: node.name,
          parent_id: folder_ids[node.parent_source_id],
          state: node.dropped ? :dropped : :active
        )
        record_item!(kind: :folder, source_id: node.source_id, extras: node.extras, project_folder: folder)
        created["folders"] += 1
        folder.id
      end

      def apply_projects(projects, folder_ids, created, skipped)
        ids = {}
        projects.each do |node|
          if (item = existing[node.source_id])
            skipped["projects"] += 1
            item.project&.update!(notes: node.notes) if node.notes.present?
            ids[node.source_id] = item.project_id
            next
          end

          project = @user.projects.create!(
            title: node.title,
            notes: node.notes,
            project_folder_id: folder_ids[node.folder_source_id],
            state: node.state
          )
          record_item!(kind: :project, source_id: node.source_id, extras: node.extras, project: project)
          created["projects"] += 1
          ids[node.source_id] = project.id
        end
        ids
      end

      def apply_tasks(tasks, project_ids, created, skipped)
        tasks.each do |node|
          if (item = existing[node.source_id])
            skipped["tasks"] += 1
            item.task&.update!(notes: node.notes) if node.notes.present?
            next
          end

          inbox = node.inbox || node.project_source_id.blank?
          task = @user.tasks.create!(
            title: node.title,
            notes: node.notes,
            inbox: inbox,
            project_id: inbox ? nil : project_ids[node.project_source_id],
            state: node.state
          )
          record_item!(kind: :task, source_id: node.source_id, extras: node.extras, task: task)
          created["tasks"] += 1
        end
      end

      def record_item!(kind:, source_id:, extras:, project_folder: nil, project: nil, task: nil)
        item = @user.import_items.create!(
          import_batch: @batch,
          source: @batch.source,
          kind: kind,
          source_id: source_id,
          extras: extras || {},
          project_folder: project_folder,
          project: project,
          task: task
        )
        existing[source_id] = item
      end
  end
end
