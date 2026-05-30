defmodule Vtex do
  @moduledoc """
  Vtex — a streaming VT/ANSI escape-sequence parser for Elixir.

  Vtex turns a raw byte stream (from an SSH/Telnet/TCP transport) into typed
  tokens and, optionally, semantic input events. It is the input-parsing
  equivalent of the Rust [`vte`](https://crates.io/crates/vte) crate, and is
  intended for SSH/Telnet game servers, BBS engines and MUD frameworks.

  The library is transport-agnostic: it knows nothing about SSH, Telnet or TCP.
  Output encoding is deliberately out of scope — use `IO.ANSI` for that.

  ## Pipeline

      raw bytes
        -> Vtex.Stream    # stateful: buffers partial sequences, caps memory
        -> Vtex.Tokenizer # pure: bytes -> tokens
        -> Vtex.Input     # pure: tokens -> semantic events
        -> your game / app logic

  ## Example

      stream = Vtex.Stream.new()

      {tokens, _stream} = Vtex.Stream.feed(stream, <<0x1B, ?[, ?A, ?h, ?i>>)
      #=> {[{:csi, "", "", ?A}, {:text, "hi"}], %Vtex.Stream{}}

      Vtex.Input.interpret(tokens)
      #=> [:arrow_up, {:char, ?h}, {:char, ?i}]

  See `Vtex.Tokenizer`, `Vtex.Stream`, `Vtex.Input` and `Vtex.SGR` for details.
  """
end
