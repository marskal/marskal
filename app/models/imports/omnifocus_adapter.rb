# frozen_string_literal: true

require "zip"

module Imports
  class OmnifocusAdapter
    SOURCE = "omnifocus"
    INNER_ZIP = /\.zip\z/i
    MASTER_PREFIX = "00000000000000="
    MERGE_NAME = /\A[^=]+=[^=+]+\+[^=+]+\+[^=+]+\.zip\z/i

    def self.key
      SOURCE
    end

    def self.match?(io, filename:)
      name = filename.to_s.downcase
      return true if name.end_with?(".ofocus-backup", ".ofocus")
      return false unless zip_file?(io)

      matched = false
      Zip::File.open_buffer(read_all(io)) do |zip|
        matched = zip.any? { |entry| inner_package_entry?(entry) }
      end
      matched
    rescue Zip::Error
      false
    ensure
      io.rewind if io.respond_to?(:rewind)
    end

    def self.parse(io, filename: nil)
      new(io, filename: filename).parse
    end

    def self.zip_file?(io)
      head = io.read(4)
      io.rewind if io.respond_to?(:rewind)
      head == "PK\x03\x04"
    rescue IOError
      false
    end

    def self.read_all(io)
      io.rewind if io.respond_to?(:rewind)
      io.read
    ensure
      io.rewind if io.respond_to?(:rewind)
    end

    def self.inner_package_entry?(entry)
      return false if entry.directory?
      return false if entry.name.include?("..")
      File.basename(entry.name).match?(INNER_ZIP) || File.basename(entry.name) == "contents.xml"
    end

    def initialize(io, filename: nil)
      @bytes = self.class.read_all(io)
      @filename = filename.to_s
    end

    def parse
      documents = xml_documents
      raise ArgumentError, "No OmniFocus contents.xml found in the backup." if documents.empty?

      folders = {}
      tasks = {}
      documents.each do |xml|
        apply_document(xml, folders, tasks)
      end

      Graph.new(
        source: SOURCE,
        folders: folder_nodes(folders),
        projects: project_nodes(tasks),
        tasks: task_nodes(tasks)
      )
    end

    private
      def xml_documents
        entries = []
        Zip::File.open_buffer(@bytes) do |zip|
          zip.each do |entry|
            raise ArgumentError, "Unsafe zip entry #{entry.name}" if entry.name.include?("..") || entry.name.start_with?("/")

            base = File.basename(entry.name)
            next if entry.directory?
            next if MERGE_NAME.match?(base)
            next if base.end_with?(".client")

            if base == "contents.xml"
              entries << [ sort_key(base), entry.get_input_stream.read ]
            elsif base.match?(INNER_ZIP)
              inner = entry.get_input_stream.read
              xml = xml_from_inner_zip(inner)
              entries << [ sort_key(base), xml ] if xml
            end
          end
        end
        entries.sort_by(&:first).map(&:last)
      end

      def sort_key(basename)
        return [ 0, "" ] if basename.start_with?(MASTER_PREFIX) || basename == "contents.xml"

        stamp = basename.split("=", 2).first.to_s
        [ 1, stamp ]
      end

      def xml_from_inner_zip(bytes)
        xml = nil
        Zip::File.open_buffer(bytes) do |inner|
          entry = inner.entries.find { |e| File.basename(e.name) == "contents.xml" }
          next unless entry
          raise ArgumentError, "Unsafe zip entry #{entry.name}" if entry.name.include?("..")

          xml = entry.get_input_stream.read
        end
        xml
      rescue Zip::Error
        nil
      end

      def apply_document(xml, folders, tasks)
        doc = Nokogiri::XML(xml)
        doc.remove_namespaces!
        root = doc.root
        return unless root

        root.element_children.each do |el|
          case el.name
          when "folder"
            apply_record(folders, el) { parse_folder(el) }
          when "task"
            apply_record(tasks, el) { parse_task(el) }
          end
        end
      end

      def apply_record(store, el)
        id = el["id"]
        return if id.blank?

        case el["op"]
        when "reference"
          store[id] ||= yield
        when "delete"
          store.delete(id)
        else
          incoming = yield
          store[id] = store[id] ? store[id].merge(incoming) { |_k, old, new| new.nil? ? old : new } : incoming
        end
      end

      def parse_folder(el)
        parent = el.at_xpath("./folder[@idref]")
        {
          "id" => el["id"],
          "name" => text_at(el, "name"),
          "parent_id" => parent&.[]("idref"),
          "hidden" => text_at(el, "hidden") == "true"
        }
      end

      def parse_task(el)
        project_el = el.at_xpath("./project")
        parent = el.at_xpath("./task[@idref]")
        {
          "id" => el["id"],
          "name" => text_at(el, "name"),
          "notes" => notes_at(el),
          "inbox" => el.at_xpath("./inbox").present?,
          "parent_id" => parent&.[]("idref"),
          "completed" => text_at(el, "completed"),
          "start" => text_at(el, "start"),
          "due" => text_at(el, "due"),
          "planned" => text_at(el, "planned"),
          "flagged" => text_at(el, "flagged") == "true",
          "repeat" => text_at(el, "repeat") || text_at(el, "repetition-rule"),
          "project" => project_el && {
            "folder_id" => project_el.at_xpath("./folder[@idref]")&.[]("idref"),
            "status" => text_at(project_el, "status").presence || "active"
          },
          "tag_ids" => el.xpath("./tag[@idref]|./context[@idref]").map { |n| n["idref"] }
        }
      end

      def text_at(el, name)
        child = el.at_xpath("./#{name}")
        return if child.nil?

        child.text.presence
      end

      def notes_at(el)
        node = el.at_xpath("./note")
        return if node.nil?

        ActionView::Base.full_sanitizer.sanitize(node.text.to_s).squish.presence
      end

      def folder_nodes(folders)
        folders.values.map do |row|
          Folder.new(
            source_id: row["id"],
            name: row["name"].presence || "Untitled folder",
            parent_source_id: row["parent_id"],
            dropped: row["hidden"] == true,
            extras: {}
          )
        end
      end

      def project_nodes(tasks)
        tasks.values.filter_map do |row|
          next unless row["project"]

          ProjectNode.new(
            source_id: row["id"],
            title: row["name"].presence || "Untitled project",
            notes: row["notes"],
            folder_source_id: row["project"]["folder_id"],
            state: project_state(row["project"]["status"], row["completed"]),
            extras: extras_for(row)
          )
        end
      end

      def task_nodes(tasks)
        project_ids = tasks.values.filter_map { |row| row["id"] if row["project"] }.to_set

        tasks.values.filter_map do |row|
          next if row["project"]

          project_id, parent_id = resolve_project(row, tasks, project_ids)
          TaskNode.new(
            source_id: row["id"],
            title: row["name"].presence || "Untitled task",
            notes: row["notes"],
            inbox: row["inbox"] == true || project_id.blank?,
            project_source_id: project_id,
            parent_source_id: parent_id,
            state: task_state(row),
            extras: extras_for(row).merge("parent_source_id" => parent_id).compact
          )
        end
      end

      def resolve_project(row, tasks, project_ids)
        parent_id = row["parent_id"]
        walker = parent_id
        seen = Set.new
        while walker.present? && seen.add?(walker)
          return [ walker, parent_id ] if project_ids.include?(walker)

          walker = tasks.dig(walker, "parent_id")
        end
        [ nil, parent_id ]
      end

      def project_state(status, completed)
        return "done" if completed.present? || status == "done"
        return "dropped" if status == "dropped"
        "to_do"
      end

      def task_state(row)
        return "done" if row["completed"].present?
        return "dropped" if row.dig("project", "status") == "dropped"
        "to_do"
      end

      def extras_for(row)
        extras = {}
        extras["defer_until"] = row["start"] if row["start"].present?
        extras["due"] = row["due"] if row["due"].present?
        extras["planned"] = row["planned"] if row["planned"].present?
        extras["flagged"] = true if row["flagged"]
        extras["repeat"] = row["repeat"] if row["repeat"].present?
        extras["tag_ids"] = row["tag_ids"] if row["tag_ids"].present?
        extras["defer"] = "indefinite" if row.dig("project", "status") == "inactive"
        extras
      end
  end
end
