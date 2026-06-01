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
        -> Vtex.Input.Stream    # stateful: buffers partial sequences, caps memory
        -> Vtex.Input.Tokenizer # pure: bytes -> tokens
        -> Vtex.Input     # pure: tokens -> semantic events
        -> your game / app logic

      stream = Vtex.Input.Stream.new()

      {tokens, _stream} = Vtex.Input.Stream.feed(stream, <<0x1B, ?[, ?A, ?h, ?i>>)
      #=> {[{:csi, "", "", ?A}, {:text, "hi"}], %Vtex.Input.Stream{}}

      Vtex.Input.interpret(tokens)
      #=> [:arrow_up, {:char, ?h}, {:char, ?i}]

  ## Output

  `Vtex.Output.ANSI` is a drop-in superset of `IO.ANSI` (verified byte-for-byte) with
  24-bit truecolor on top. Output functions return iodata to write:

      transport_write([
        Vtex.Output.Screen.clear(),
        Vtex.Output.ANSI.cursor(1, 1),
        Vtex.Output.ANSI.format([:bright, Vtex.Output.ANSI.true_color(255, 128, 0), "Hello"])
      ])

  ## Modules

  Input: `Vtex.Input.Stream`, `Vtex.Input.Tokenizer`, `Vtex.Input`.
  Output: `Vtex.Output.ANSI` (IO.ANSI-compatible colour/style/cursor + truecolor),
  `Vtex.Output.Cursor`, `Vtex.Output.Screen`, `Vtex.Output.OSC` (title, hyperlinks), `Vtex.SGR`
  (`encode/1`).
  Both: `Vtex.SGR` (parse + encode), and the mode toggles `Vtex.Mouse`,
  `Vtex.Paste`, `Vtex.Focus` (whose events also feed `Vtex.Input`).

  ## Restoring the terminal on exit

  The modes you set (colours, hidden cursor, alternate buffer, mouse tracking)
  are *terminal* state and outlive your process, so undo them before you exit —
  ideally from a `try/after` or signal handler so it runs even on a crash.
  `restore/0` returns a safe, all-in-one teardown:

      try do
        transport_write(Vtex.Output.Screen.enter_alternate())
        run_app()
      after
        transport_write(Vtex.restore())
      end
  """

  @doc """
  Returns a full teardown sequence that restores the terminal to a sane state:
  clears SGR attributes, resets the cursor shape and shows the cursor, resets the
  scroll region, disables mouse/bracketed-paste/focus reporting, and leaves the
  alternate buffer (last, so the user lands back on the primary screen).

  Each step is the inverse of a Vtex setup function. Disabling a mode you never
  enabled is harmless, so this is safe to emit unconditionally — for example from
  a `try/after` or a crash handler where you don't track exactly what was on. For
  a surgical exit, emit only the specific inverse functions instead.

  ## Examples

      iex> Vtex.restore() |> IO.iodata_to_binary()
      "\\e[0m\\e[0 q\\e[?25h\\e[r\\e[?1006l\\e[?1003l\\e[?1002l\\e[?1000l\\e[?2004l\\e[?1004l\\e[?1049l"
  """
  @spec restore() :: iodata()
  def restore do
    alias Vtex.Output.{ANSI, Cursor, Screen}

    [
      ANSI.reset(),
      Cursor.reset_shape(),
      Cursor.show(),
      Screen.reset_scroll_region(),
      Vtex.Mouse.disable(),
      Vtex.Paste.disable(),
      Vtex.Focus.disable(),
      Screen.leave_alternate()
    ]
  end
end
