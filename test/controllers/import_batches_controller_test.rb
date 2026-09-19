# frozen_string_literal: true

require "test_helper"
require "test_helpers/omnifocus_backup"

class ImportBatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "index requires sign in" do
    sign_out
    get import_batches_path
    assert_redirected_to new_session_path
  end

  test "upload parses and previews" do
    file = Tempfile.new([ "OmniFocus", ".ofocus-backup" ])
    file.binmode
    file.write(OmnifocusBackup.compact_backup)
    file.rewind
    upload = Rack::Test::UploadedFile.new(file.path, "application/zip", true)
    upload.instance_variable_set(:@original_filename, "OmniFocus.ofocus-backup")

    assert_difference -> { @user.import_batches.count }, 1 do
      post import_batches_path, params: {
        import_batch: { payload: upload }
      }
    end

    batch = @user.import_batches.order(:created_at).last
    assert_redirected_to import_batch_path(batch)
    perform_enqueued_jobs
    batch.reload
    assert batch.previewed?
    assert_equal 2, batch.stats["folders"]
    assert_equal 1, batch.stats["projects"]
  ensure
    file.close!
  end

  test "upload ofocus-backup package members as a bundle" do
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

    assert_difference -> { @user.import_batches.count }, 1 do
      post import_batches_path, params: {
        import_batch: { bundle_files: files, bundle_paths: paths }
      }
    end

    batch = @user.import_batches.order(:created_at).last
    assert_redirected_to import_batch_path(batch)
    perform_enqueued_jobs
    batch.reload
    assert batch.previewed?
    assert_equal 2, batch.stats["projects"]
  ensure
    tempfiles&.each { |tmp| tmp.close! }
  end

  test "apply writes records" do
    batch = @user.import_batches.new(source: "omnifocus", channel: :file, status: :pending)
    batch.payload.attach(
      io: StringIO.new(OmnifocusBackup.compact_backup),
      filename: "OmniFocus.ofocus-backup",
      content_type: "application/zip"
    )
    batch.save!
    Imports::Parser.call(batch)

    post apply_import_batch_path(batch)
    perform_enqueued_jobs
    assert_redirected_to import_batch_path(batch)
    assert batch.reload.applied?
    assert @user.tasks.find_by(title: "Buy milk")
  end

  test "cannot show another users batch" do
    batch = users(:two).import_batches.new(source: "omnifocus", channel: :file, status: :failed)
    batch.save!(validate: false)
    get import_batch_path(batch)
    assert_response :not_found
  end
end
