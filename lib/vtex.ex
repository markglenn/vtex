defmodule Vtex do
  @moduledoc """
  Vtex — a streaming VT/ANSI escape-sequence library for Elixir.

  Vtex handles terminal I/O in both directions: it turns a raw byte stream (from
  an SSH/Telnet/TCP transport) into typed tokens and semantic input events, and
  it builds the control sequences you write back to draw the screen. It is
  intended for SSH/Telnet game servers, BBS engines and MUD frameworks.

  The library is transport-agnostic and does no IO of its own: input functions
  take bytes you've read, output functions return bytes for you to write.

  ## Input pipeline

      raw bytes
        -> Vtex.Stream    # stateful: buffers partial sequences, caps memory
        -> Vtex.Tokenizer # pure: bytes -> tokens
        -> Vtex.Input     # pure: tokens -> semantic events
        -> your game / app logic

      stream = Vtex.Stream.new()

      {tokens, _stream} = Vtex.Stream.feed(stream, <<0x1B, ?[, ?A, ?h, ?i>>)
      #=> {[{:csi, "", "", ?A}, {:text, "hi"}], %Vtex.Stream{}}

      Vtex.Input.interpret(tokens)
      #=> [:arrow_up, {:char, ?h}, {:char, ?i}]

  ## Output

  Output functions return iodata to write to the terminal:

      transport_write([
        Vtex.Screen.clear(),
        Vtex.Cursor.to(1, 1),
        Vtex.SGR.encode([:bold, {:fg, :red}]),
        "Hello",
        Vtex.SGR.encode([:reset])
      ])

  ## Modules

  Input: `Vtex.Stream`, `Vtex.Tokenizer`, `Vtex.Input`.
  Output: `Vtex.Cursor`, `Vtex.Screen`, `Vtex.SGR` (`encode/1`).
  Both: `Vtex.SGR` (parse + encode), and the mode toggles `Vtex.Mouse`,
  `Vtex.Paste`, `Vtex.Focus` (whose events also feed `Vtex.Input`).
  """
end
