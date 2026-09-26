defmodule OmnifocusBackup do
  @moduledoc false

  @xml """
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
  """

  def compact_backup do
    inner = zip([{"contents.xml", @xml}])
    zip([{"00000000000000=AAAAAAAAAAA+BBBBBBBBBBB.zip", inner}])
  end

  def tutorial_backup do
    Path.expand("../fixtures/files/omnifocus-tutorial.ofocus-backup.zip", __DIR__)
    |> File.read!()
  end

  def zip_with_xml(xml), do: zip([{"contents.xml", xml}])

  def zip_slip_archive, do: zip([{"../evil.xml", "<omnifocus/>"}])

  def zip(entries) do
    files = Enum.map(entries, fn {name, data} -> {to_charlist(name), data} end)

    case :zip.zip(~c"omnifocus.zip", files, [:memory]) do
      {:ok, {_name, bin}} -> bin
      {:error, reason} -> raise "could not build zip: #{inspect(reason)}"
    end
  end
end
