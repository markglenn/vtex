defmodule Vtex.Output.Cursor do
  @moduledoc """
  Cursor-control output sequences.

  Every function returns the bytes of a control sequence for you to write to the
  terminal; the library performs no IO of its own. Positions are 1-based, matching
  the terminal's own convention.

      transport_write([Vtex.Output.Cursor.to(1, 1), Vtex.Output.Cursor.hide()])
  """

  @doc """
  Move the cursor to `row`, `col` (both 1-based).

  ## Examples

      iex> Vtex.Output.Cursor.to(5, 10)
      "\\e[5;10H"
  """
  @spec to(pos_integer(), pos_integer()) :: binary()
  def to(row, col) when row >= 1 and col >= 1, do: "\e[#{row};#{col}H"

  @doc """
  Move the cursor to `col` on the current row (1-based).

  ## Examples

      iex> Vtex.Output.Cursor.column(1)
      "\\e[1G"
  """
  @spec column(pos_integer()) :: binary()
  def column(col) when col >= 1, do: "\e[#{col}G"

  @doc """
  Move the cursor to `row` on the current column (1-based). This is the vertical
  counterpart to `column/1`.

  ## Examples

      iex> Vtex.Output.Cursor.row(5)
      "\\e[5d"
  """
  @spec row(pos_integer()) :: binary()
  def row(row) when row >= 1, do: "\e[#{row}d"

  @doc """
  Move the cursor `n` cells in a direction.

    * `:up`, `:down`, `:left`, `:right` — move within the current column/row.
    * `:next_line`, `:prev_line` — move `n` rows down/up **and** to column 1.

  ## Examples

      iex> Vtex.Output.Cursor.move(:up, 3)
      "\\e[3A"

      iex> Vtex.Output.Cursor.move(:right)
      "\\e[1C"

      iex> Vtex.Output.Cursor.move(:next_line, 2)
      "\\e[2E"
  """
  @spec move(:up | :down | :left | :right | :next_line | :prev_line, pos_integer()) :: binary()
  def move(direction, n \\ 1) when n >= 1, do: "\e[#{n}#{final(direction)}"

  defp final(:up), do: "A"
  defp final(:down), do: "B"
  defp final(:right), do: "C"
  defp final(:left), do: "D"
  defp final(:next_line), do: "E"
  defp final(:prev_line), do: "F"

  @doc """
  Set the cursor shape (DECSCUSR): `:block`, `:underline`, or `:bar`, blinking
  unless `blink?` is `false`. Use `reset_shape/0` to return to the terminal
  default.

  ## Examples

      iex> Vtex.Output.Cursor.shape(:bar)
      "\\e[5 q"

      iex> Vtex.Output.Cursor.shape(:block, false)
      "\\e[2 q"
  """
  @spec shape(:block | :underline | :bar, boolean()) :: binary()
  def shape(kind, blink? \\ true)
  def shape(:block, true), do: "\e[1 q"
  def shape(:block, false), do: "\e[2 q"
  def shape(:underline, true), do: "\e[3 q"
  def shape(:underline, false), do: "\e[4 q"
  def shape(:bar, true), do: "\e[5 q"
  def shape(:bar, false), do: "\e[6 q"

  @doc """
  Reset the cursor shape to the terminal default (DECSCUSR 0).

  ## Examples

      iex> Vtex.Output.Cursor.reset_shape()
      "\\e[0 q"
  """
  @spec reset_shape() :: binary()
  def reset_shape, do: "\e[0 q"

  @doc """
  Request a cursor position report (DSR). The terminal replies with
  `\\e[<row>;<col>R`, which arrives on the input stream and tokenizes as a
  `{:csi, "<row>;<col>", "", ?R}` token.

  ## Examples

      iex> Vtex.Output.Cursor.request_position()
      "\\e[6n"
  """
  @spec request_position() :: binary()
  def request_position, do: "\e[6n"

  @doc """
  Save the cursor position (DECSC). Pair with `restore/0`.

  ## Examples

      iex> Vtex.Output.Cursor.save()
      "\\e7"
  """
  @spec save() :: binary()
  def save, do: "\e7"

  @doc """
  Restore the cursor position saved by `save/0` (DECRC).

  ## Examples

      iex> Vtex.Output.Cursor.restore()
      "\\e8"
  """
  @spec restore() :: binary()
  def restore, do: "\e8"

  @doc """
  Hide the cursor.

  ## Examples

      iex> Vtex.Output.Cursor.hide()
      "\\e[?25l"
  """
  @spec hide() :: binary()
  def hide, do: "\e[?25l"

  @doc """
  Show the cursor.

  ## Examples

      iex> Vtex.Output.Cursor.show()
      "\\e[?25h"
  """
  @spec show() :: binary()
  def show, do: "\e[?25h"
end
