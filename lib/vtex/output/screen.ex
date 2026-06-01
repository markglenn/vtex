defmodule Vtex.Output.Screen do
  @moduledoc """
  Screen-control output sequences: clearing, the alternate buffer, scroll
  regions, scrolling, line/character editing, and synchronized updates.

  Every function returns the bytes of a control sequence for you to write to the
  terminal; the library performs no IO of its own.

  The alternate screen buffer is what full-screen apps (editors, pagers) use so
  the user's scrollback is restored on exit:

      transport_write(Vtex.Output.Screen.enter_alternate())
      # ... draw the UI ...
      transport_write(Vtex.Output.Screen.leave_alternate())

  For flicker-free partial redraws, wrap each frame in a synchronized update so
  the terminal presents it atomically:

      transport_write([
        Vtex.Output.Screen.begin_sync(),
        # ... only the cells that changed ...
        Vtex.Output.Screen.end_sync()
      ])
  """

  @doc """
  Clear the whole screen (does not move the cursor).

  ## Examples

      iex> Vtex.Output.Screen.clear()
      "\\e[2J"
  """
  @spec clear() :: binary()
  def clear, do: "\e[2J"

  @doc """
  Clear from the cursor to the end of the screen.

  ## Examples

      iex> Vtex.Output.Screen.clear_below()
      "\\e[0J"
  """
  @spec clear_below() :: binary()
  def clear_below, do: "\e[0J"

  @doc """
  Clear from the start of the screen to the cursor.

  ## Examples

      iex> Vtex.Output.Screen.clear_above()
      "\\e[1J"
  """
  @spec clear_above() :: binary()
  def clear_above, do: "\e[1J"

  @doc """
  Clear the current line (does not move the cursor).

  ## Examples

      iex> Vtex.Output.Screen.clear_line()
      "\\e[2K"
  """
  @spec clear_line() :: binary()
  def clear_line, do: "\e[2K"

  @doc """
  Clear from the cursor to the end of the line.

  ## Examples

      iex> Vtex.Output.Screen.clear_line_end()
      "\\e[0K"
  """
  @spec clear_line_end() :: binary()
  def clear_line_end, do: "\e[0K"

  @doc """
  Clear from the start of the line to the cursor.

  ## Examples

      iex> Vtex.Output.Screen.clear_line_start()
      "\\e[1K"
  """
  @spec clear_line_start() :: binary()
  def clear_line_start, do: "\e[1K"

  @doc """
  Switch to the alternate screen buffer (saving the primary screen).

  ## Examples

      iex> Vtex.Output.Screen.enter_alternate()
      "\\e[?1049h"
  """
  @spec enter_alternate() :: binary()
  def enter_alternate, do: "\e[?1049h"

  @doc """
  Leave the alternate screen buffer, restoring the primary screen.

  ## Examples

      iex> Vtex.Output.Screen.leave_alternate()
      "\\e[?1049l"
  """
  @spec leave_alternate() :: binary()
  def leave_alternate, do: "\e[?1049l"

  @doc """
  Set the scroll region to rows `top`..`bottom` (1-based, inclusive).

  ## Examples

      iex> Vtex.Output.Screen.scroll_region(2, 23)
      "\\e[2;23r"
  """
  @spec scroll_region(pos_integer(), pos_integer()) :: binary()
  def scroll_region(top, bottom) when top >= 1 and bottom >= top, do: "\e[#{top};#{bottom}r"

  @doc """
  Reset the scroll region to the full screen.

  ## Examples

      iex> Vtex.Output.Screen.reset_scroll_region()
      "\\e[r"
  """
  @spec reset_scroll_region() :: binary()
  def reset_scroll_region, do: "\e[r"

  @doc """
  Scroll the scroll region up by `n` lines (SU); blank lines appear at the bottom.

  ## Examples

      iex> Vtex.Output.Screen.scroll_up(3)
      "\\e[3S"
  """
  @spec scroll_up(pos_integer()) :: binary()
  def scroll_up(n \\ 1) when n >= 1, do: "\e[#{n}S"

  @doc """
  Scroll the scroll region down by `n` lines (SD); blank lines appear at the top.

  ## Examples

      iex> Vtex.Output.Screen.scroll_down(2)
      "\\e[2T"
  """
  @spec scroll_down(pos_integer()) :: binary()
  def scroll_down(n \\ 1) when n >= 1, do: "\e[#{n}T"

  @doc """
  Insert `n` blank lines at the cursor row (IL); lines below are pushed down.

  ## Examples

      iex> Vtex.Output.Screen.insert_lines(1)
      "\\e[1L"
  """
  @spec insert_lines(pos_integer()) :: binary()
  def insert_lines(n \\ 1) when n >= 1, do: "\e[#{n}L"

  @doc """
  Delete `n` lines starting at the cursor row (DL); lines below move up.

  ## Examples

      iex> Vtex.Output.Screen.delete_lines(1)
      "\\e[1M"
  """
  @spec delete_lines(pos_integer()) :: binary()
  def delete_lines(n \\ 1) when n >= 1, do: "\e[#{n}M"

  @doc """
  Insert `n` blank characters at the cursor (ICH); characters to the right shift over.

  ## Examples

      iex> Vtex.Output.Screen.insert_chars(2)
      "\\e[2@"
  """
  @spec insert_chars(pos_integer()) :: binary()
  def insert_chars(n \\ 1) when n >= 1, do: "\e[#{n}@"

  @doc """
  Delete `n` characters at the cursor (DCH); characters to the right shift left.

  ## Examples

      iex> Vtex.Output.Screen.delete_chars(2)
      "\\e[2P"
  """
  @spec delete_chars(pos_integer()) :: binary()
  def delete_chars(n \\ 1) when n >= 1, do: "\e[#{n}P"

  @doc """
  Erase `n` characters at the cursor (ECH), replacing them with blanks without
  shifting the rest of the line.

  ## Examples

      iex> Vtex.Output.Screen.erase_chars(4)
      "\\e[4X"
  """
  @spec erase_chars(pos_integer()) :: binary()
  def erase_chars(n \\ 1) when n >= 1, do: "\e[#{n}X"

  @doc """
  Begin a synchronized update (DEC mode 2026). The terminal buffers everything
  until `end_sync/0`, then presents it as a single frame — eliminating tearing on
  partial redraws. Terminals that don't support it ignore the sequence.

  ## Examples

      iex> Vtex.Output.Screen.begin_sync()
      "\\e[?2026h"
  """
  @spec begin_sync() :: binary()
  def begin_sync, do: "\e[?2026h"

  @doc """
  End a synchronized update started with `begin_sync/0`, flushing the frame.

  ## Examples

      iex> Vtex.Output.Screen.end_sync()
      "\\e[?2026l"
  """
  @spec end_sync() :: binary()
  def end_sync, do: "\e[?2026l"

  @doc """
  Soft terminal reset (DECSTR). Resets the *drawing* state — SGR attributes,
  cursor visibility, origin mode, and the scroll region — without clearing the
  screen.

  Note this does **not** leave the alternate buffer or disable mouse, bracketed
  paste, or focus reporting; for a full exit, disable those explicitly (see
  `Vtex.restore/0`).

  ## Examples

      iex> Vtex.Output.Screen.soft_reset()
      "\\e[!p"
  """
  @spec soft_reset() :: binary()
  def soft_reset, do: "\e[!p"

  @doc """
  Full terminal reset (RIS). Equivalent to power-cycling the terminal: clears the
  screen, resets the palette and all modes, and returns to the primary buffer.
  Heavy-handed and visible — prefer a paired teardown (`Vtex.restore/0`) for
  normal exits, and reserve this for last-resort recovery.

  ## Examples

      iex> Vtex.Output.Screen.full_reset()
      "\\ec"
  """
  @spec full_reset() :: binary()
  def full_reset, do: "\ec"
end
