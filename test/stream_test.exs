defmodule Vtex.StreamTest do
  use ExUnit.Case, async: true
  doctest Vtex.Stream

  alias Vtex.Stream

  @esc 0x1B

  test "new/0 starts with an empty buffer" do
    assert Stream.new() == %Stream{buffer: ""}
  end

  test "feeds complete input with no leftover" do
    {tokens, stream} = Stream.feed(Stream.new(), "hi")
    assert tokens == [{:text, "hi"}]
    assert stream.buffer == ""
  end

  describe "chunked input across feeds" do
    test "a CSI split across two chunks is reassembled" do
      stream = Stream.new()

      {tokens1, stream} = Stream.feed(stream, <<@esc, ?[>>)
      assert tokens1 == []
      assert stream.buffer == <<@esc, ?[>>

      {tokens2, stream} = Stream.feed(stream, <<?A>>)
      assert tokens2 == [{:csi, "", "", ?A}]
      assert stream.buffer == ""
    end

    test "an OSC split byte-by-byte is reassembled" do
      data = <<@esc, ?], "0;t", 0x07>>

      {tokens, stream} =
        Enum.reduce(:binary.bin_to_list(data), {[], Stream.new()}, fn byte, {acc, stream} ->
          {tokens, stream} = Stream.feed(stream, <<byte>>)
          {acc ++ tokens, stream}
        end)

      assert tokens == [{:osc, "0;t"}]
      assert stream.buffer == ""
    end

    test "text before a partial sequence is emitted immediately" do
      {tokens, stream} = Stream.feed(Stream.new(), <<?h, ?i, @esc, ?[>>)
      assert tokens == [{:text, "hi"}]
      assert stream.buffer == <<@esc, ?[>>
    end
  end

  describe "buffer cap" do
    test "max_buffer/0 is 256" do
      assert Stream.max_buffer() == 256
    end

    test "an oversized unterminated sequence is flushed as invalid and buffer cleared" do
      # Unterminated OSC longer than the cap.
      payload = String.duplicate("A", 300)
      {tokens, stream} = Stream.feed(Stream.new(), <<@esc, ?], payload::binary>>)

      assert [{:invalid, invalid}] = tokens
      assert byte_size(invalid) > Stream.max_buffer()
      assert stream.buffer == ""
    end

    test "input exactly at the cap is retained, not flushed" do
      payload = String.duplicate("A", Stream.max_buffer() - 2)
      data = <<@esc, ?], payload::binary>>
      assert byte_size(data) == Stream.max_buffer()

      {tokens, stream} = Stream.feed(Stream.new(), data)
      assert tokens == []
      assert stream.buffer == data
    end

    test "valid tokens are still emitted alongside an oversized flush" do
      payload = String.duplicate("A", 300)
      data = <<?h, ?i, @esc, ?], payload::binary>>

      {tokens, stream} = Stream.feed(Stream.new(), data)
      assert [{:text, "hi"}, {:invalid, _}] = tokens
      assert stream.buffer == ""
    end
  end
end
