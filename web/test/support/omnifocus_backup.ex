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
      <flagged>true</flagged>
      <note><text>Public site</text></note>
      <added>2024-01-02T00:00:00.000Z</added>
      <rank>3</rank>
    </task>
    <task id="taskDraft000">
      <task idref="projSite0000"/>
      <name>Draft homepage</name>
      <due>2024-03-01T16:00:00.000Z</due>
      <start>2024-02-20T08:00:00.000Z</start>
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
      <flagged>true</flagged>
      <added>2024-01-05T00:00:00.000Z</added>
      <rank>6</rank>
    </task>
    <task id="taskBoth0000">
      <inbox/>
      <task idref="projSite0000"/>
      <name>Order business cards</name>
      <added>2024-01-06T00:00:00.000Z</added>
      <rank>7</rank>
    </task>
  </omnifocus>
  """

  # Tags are <context> records. ctxHome2 differs from ctxHome1 only in
  # case, and a link names a tag the backup does not define.
  @tagged_xml """
  <?xml version="1.0" encoding="UTF-8"?>
  <omnifocus>
    <context id="ctxPerson00"><context/><name>Person</name><rank>20</rank><hidden/><prohibits-next-action>false</prohibits-next-action></context>
    <context id="ctxWife0000"><context idref="ctxPerson00"/><name>Wife</name><rank>0</rank></context>
    <context id="ctxWait0000"><context/><name>Waiting</name><rank>10</rank><prohibits-next-action>true</prohibits-next-action></context>
    <context id="ctxOld00000"><context/><name>Old</name><rank>40</rank><hidden>true</hidden></context>
    <context id="ctxHome1000"><context/><name>Home</name><rank>30</rank></context>
    <context id="ctxHome2000"><context/><name>home</name><rank>35</rank></context>
    <task id="projGarden0">
      <project><status>active</status></project>
      <name>Garden</name>
    </task>
    <task id="taskCall000">
      <task idref="projGarden0"/>
      <context idref="ctxWife0000"/>
      <name>Call about the hedge</name>
    </task>
    <task id="taskFix0000">
      <inbox/>
      <name>Fix tap</name>
    </task>
    <task-to-tag id="projGarden0.ctxHome1000"><task idref="projGarden0"/><context idref="ctxHome1000"/></task-to-tag>
    <task-to-tag id="taskCall000.ctxWait0000"><task idref="taskCall000"/><context idref="ctxWait0000"/></task-to-tag>
    <task-to-tag id="taskFix0000.ctxHome2000"><task idref="taskFix0000"/><context idref="ctxHome2000"/></task-to-tag>
    <task-to-tag id="taskFix0000.ctxGone0000"><task idref="taskFix0000"/><context idref="ctxGone0000"/></task-to-tag>
  </omnifocus>
  """

  def tagged_backup, do: zip_with_xml(@tagged_xml)

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
