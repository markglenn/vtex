defmodule Vtex.Output.Screen do
  @moduledoc """
  Screen-control output sequences: clearing, the alternate buffer, scroll regions.

  Every function returns the bytes of a control sequence for you to write to the
  terminal; the library performs no IO of its own.

  The alternate screen buffer is what full-screen apps (editors, pagers) use so
  the user's scrollback is restored on exit:

      transport_write(Vtex.Output.Screen.enter_alternate())
      # ... draw the UI ...
      transport_write(Vtex.Output.Screen.leave_alternate())
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
end
