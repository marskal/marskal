defmodule Marskal.UuidTest do
  use ExUnit.Case, async: true

  alias Marskal.Tags.Link
  alias Marskal.Uuid

  # Expected values come from Python's uuid.uuid5, an independent
  # implementation.
  test "v5 of a DNS name, as in RFC 9562" do
    assert Uuid.v5("6ba7b810-9dad-11d1-80b4-00c04fd430c8", "www.marskal.example") ==
             "4b130f8d-0c48-5558-8073-f785abf579b7"
  end

  test "v5 hashes the UTF-8 bytes of the name" do
    assert Uuid.v5("a5c0ffee-0005-5000-8000-000000000005", "Ærø ☕") ==
             "8703676c-2e18-5038-9142-791a5ca2d8e4"
  end

  test "tag link ids match the ADR 0005 vectors" do
    tag = "0191d3a6-0000-7000-8000-000000000002"

    assert Link.id(:task, "0191d3a6-0000-7000-8000-000000000001", tag) ==
             "af08b623-24ef-5e96-91d7-4411e930931b"

    assert Link.id(:project, "0191D3A6-0000-7000-8000-000000000003", tag) ==
             "aeb6e344-5a08-5f9a-aa68-0ec67f849ffc"
  end
end
