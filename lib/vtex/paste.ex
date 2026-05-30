defmodule Vtex.Paste do
  @moduledoc """
  Bracketed paste support: the control sequences that turn it on and off.

  When enabled (`enable/0`), the terminal wraps pasted text in markers —
  `ESC [ 200 ~` before and `ESC [ 201 ~` after — so a program can tell pasted
  input from typed input (and, for example, avoid treating embedded newlines as
  "submit"). `Vtex.Input` surfaces those markers as the `:paste_start` and
  `:paste_end` events; the bytes in between arrive as ordinary events.

  Accumulate the events between `:paste_start` and `:paste_end` to reconstruct
  the pasted text, applying your own size limit — the parser is stateless and
  deliberately does not buffer the paste for you, so a never-terminated paste
  can't exhaust memory.

  Like `Vtex.Mouse`, `enable/0`/`disable/0` are part of the small amount of
  output this otherwise input-only library emits; they return bytes for you to
  write and perform no IO of their own.
  """

  @enable "\e[?2004h"
  @disable "\e[?2004l"

  @doc """
  The control sequence that enables bracketed paste. Write it to the terminal.

  ## Examples

      iex> Vtex.Paste.enable() =~ "2004h"
      true
  """
  @spec enable() :: binary()
  def enable, do: @enable

  @doc """
  The control sequence that disables bracketed paste. Write it on teardown.

  ## Examples

      iex> Vtex.Paste.disable() =~ "2004l"
      true
  """
  @spec disable() :: binary()
  def disable, do: @disable
end
