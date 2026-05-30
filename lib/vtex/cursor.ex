defmodule Vtex.Cursor do
  @moduledoc """
  Cursor-control output sequences.

  Every function returns the bytes of a control sequence for you to write to the
  terminal; the library performs no IO of its own. Positions are 1-based, matching
  the terminal's own convention.

      transport_write([Vtex.Cursor.to(1, 1), Vtex.Cursor.hide()])
  """

  @doc """
  Move the cursor to `row`, `col` (both 1-based).

  ## Examples

      iex> Vtex.Cursor.to(5, 10)
      "\\e[5;10H"
  """
  @spec to(pos_integer(), pos_integer()) :: binary()
  def to(row, col) when row >= 1 and col >= 1, do: "\e[#{row};#{col}H"

  @doc """
  Move the cursor to `col` on the current row (1-based).

  ## Examples

      iex> Vtex.Cursor.column(1)
      "\\e[1G"
  """
  @spec column(pos_integer()) :: binary()
  def column(col) when col >= 1, do: "\e[#{col}G"

  @doc """
  Move the cursor `n` cells in a direction (`:up`, `:down`, `:left`, `:right`).

  ## Examples

      iex> Vtex.Cursor.move(:up, 3)
      "\\e[3A"

      iex> Vtex.Cursor.move(:right)
      "\\e[1C"
  """
  @spec move(:up | :down | :left | :right, pos_integer()) :: binary()
  def move(direction, n \\ 1) when n >= 1, do: "\e[#{n}#{final(direction)}"

  defp final(:up), do: "A"
  defp final(:down), do: "B"
  defp final(:right), do: "C"
  defp final(:left), do: "D"

  @doc """
  Save the cursor position (DECSC). Pair with `restore/0`.

  ## Examples

      iex> Vtex.Cursor.save()
      "\\e7"
  """
  @spec save() :: binary()
  def save, do: "\e7"

  @doc """
  Restore the cursor position saved by `save/0` (DECRC).

  ## Examples

      iex> Vtex.Cursor.restore()
      "\\e8"
  """
  @spec restore() :: binary()
  def restore, do: "\e8"

  @doc """
  Hide the cursor.

  ## Examples

      iex> Vtex.Cursor.hide()
      "\\e[?25l"
  """
  @spec hide() :: binary()
  def hide, do: "\e[?25l"

  @doc """
  Show the cursor.

  ## Examples

      iex> Vtex.Cursor.show()
      "\\e[?25h"
  """
  @spec show() :: binary()
  def show, do: "\e[?25h"
end
