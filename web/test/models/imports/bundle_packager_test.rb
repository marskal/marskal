# frozen_string_literal: true

require "test_helper"
require "test_helpers/omnifocus_backup"

class Imports::BundlePackagerTest < ActiveSupport::TestCase
  test "zips package members so the OmniFocus adapter can parse them" do
    files = []
    paths = []
    tempfiles = []

    Zip::File.open_buffer(OmnifocusBackup.tutorial_backup) do |zip|
      zip.each do |entry|
        next if entry.directory?

        tmp = Tempfile.new([ "of-", File.basename(entry.name) ])
        tmp.binmode
        tmp.write(entry.get_input_stream.read)
        tmp.rewind
        tempfiles << tmp
        files << Rack::Test::UploadedFile.new(tmp.path, "application/octet-stream", true)
        paths << entry.name
      end
    end

    packed = Imports::BundlePackager.call(files: files, paths: paths)
    graph = Imports::OmnifocusAdapter.parse(packed, filename: "OmniFocus.ofocus-backup.zip")

    assert_includes graph.projects.map(&:title), "Get to know OmniFocus 4 for Mac"
    assert_includes graph.tasks.map(&:title), "Gør noget"
  ensure
    tempfiles&.each { |tmp| tmp.close! }
  end

  test "rejects zip-slip paths" do
    tmp = Tempfile.new("evil")
    tmp.write("nope")
    tmp.rewind
    file = Rack::Test::UploadedFile.new(tmp.path, "text/plain")

    assert_raises(ArgumentError) do
      Imports::BundlePackager.call(files: [ file ], paths: [ "../evil.txt" ])
    end
  ensure
    tmp.close!
  end
end
