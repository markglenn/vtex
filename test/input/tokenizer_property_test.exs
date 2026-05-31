defmodule Vtex.Input.TokenizerPropertyTest do
  @moduledoc """
  Fuzz tests: throw arbitrary byte soup at the parser and assert it stays
  well-behaved. This guards the security goals — the tokenizer parses untrusted
  bytes off the network, so for *any* input it must terminate, only ever emit
  well-formed tokens, never lose bytes, and keep the stream buffer bounded.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Vtex.Input.{Stream, Tokenizer}

  defp well_formed?({:text, b}) when is_binary(b), do: true

  defp well_formed?({:csi, p, i, f}) when is_binary(p) and is_binary(i) and is_integer(f),
    do: true

  defp well_formed?({:ss3, b}) when is_integer(b), do: true
  defp well_formed?({:osc, b}) when is_binary(b), do: true
  defp well_formed?({:esc, b}) when is_integer(b), do: true
  defp well_formed?({:invalid, b}) when is_binary(b), do: true
  defp well_formed?(_), do: false

  property "tokenize/1 terminates, emits only well-formed tokens, and never loses bytes" do
    check all(data <- binary()) do
      {tokens, leftover} = Tokenizer.tokenize(data)

      assert is_list(tokens)
      assert is_binary(leftover)
      assert Enum.all?(tokens, &well_formed?/1)

      # The leftover is exactly the unconsumed tail — a suffix of the input.
      assert byte_size(leftover) <= byte_size(data)

      assert binary_part(data, byte_size(data) - byte_size(leftover), byte_size(leftover)) ==
               leftover
    end
  end

  property "interpret/1 never crashes on tokenized random input" do
    check all(data <- binary()) do
      {tokens, _leftover} = Tokenizer.tokenize(data)
      assert is_list(Vtex.Input.interpret(tokens))
    end
  end

  property "streaming arbitrary chunks never crashes and keeps the buffer capped" do
    check all(chunks <- list_of(binary(), max_length: 12)) do
      final =
        Enum.reduce(chunks, Stream.new(), fn chunk, stream ->
          {tokens, stream} = Stream.feed(stream, chunk)
          assert is_list(tokens)
          assert Enum.all?(tokens, &well_formed?/1)
          assert byte_size(stream.buffer) <= Stream.max_buffer()
          stream
        end)

      assert byte_size(final.buffer) <= Stream.max_buffer()
    end
  end
end
