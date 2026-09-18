# frozen_string_literal: true

require "zip"

module OmnifocusBackup
  module_function

  XML = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <omnifocus>
      <folder id="folderWork00">
        <name>Work</name>
        <added>2024-01-01T00:00:00.000Z</added>
        <rank>1</rank>
      </folder>
      <folder id="folderOld000">
        <name>Old stuff</name>
        <added>2024-01-01T00:00:00.000Z</added>
        <hidden>true</hidden>
        <rank>2</rank>
      </folder>
      <task id="projSite0000">
        <project>
          <folder idref="folderWork00"/>
          <status>active</status>
        </project>
        <name>Launch website</name>
        <note><text>Public site</text></note>
        <added>2024-01-02T00:00:00.000Z</added>
        <rank>3</rank>
      </task>
      <task id="taskDraft000">
        <task idref="projSite0000"/>
        <name>Draft homepage</name>
        <added>2024-01-03T00:00:00.000Z</added>
        <rank>4</rank>
      </task>
      <task id="taskDone0000">
        <task idref="projSite0000"/>
        <name>Pick palette</name>
        <completed>2024-02-01T00:00:00.000Z</completed>
        <added>2024-01-04T00:00:00.000Z</added>
        <rank>5</rank>
      </task>
      <task id="taskInbox000">
        <inbox/>
        <name>Buy milk</name>
        <added>2024-01-05T00:00:00.000Z</added>
        <rank>6</rank>
      </task>
    </omnifocus>
  XML

  def compact_backup
    inner = Zip::OutputStream.write_buffer do |zio|
      zio.put_next_entry("contents.xml")
      zio.write XML
    end
    inner.rewind

    outer = Zip::OutputStream.write_buffer do |zio|
      zio.put_next_entry("00000000000000=AAAAAAAAAAA+BBBBBBBBBBB.zip")
      zio.write inner.read
    end
    outer.rewind
    outer.read
  end

  def zip_slip_archive
    zip = Zip::OutputStream.write_buffer do |zio|
      zio.put_next_entry("../evil.xml")
      zio.write "<omnifocus/>"
    end
    zip.rewind
    zip.read
  end
end
