defmodule Vtex.Focus do
  @moduledoc """
  Focus-reporting support: the control sequences that turn it on and off.

  When enabled (`enable/0`), the terminal reports when its window gains or loses
  focus, which `Vtex.Input` surfaces as the `:focus_in` and `:focus_out` events
  — handy for pausing a game or dimming a UI when the user tabs away.

  Like `Vtex.Mouse` and `Vtex.Paste`, `enable/0`/`disable/0` are output helpers
  that return bytes for you to write; the library performs no IO of its own.
  """

  @enable "\e[?1004h"
  @disable "\e[?1004l"

  @doc """
  The control sequence that enables focus reporting. Write it to the terminal.

  ## Examples

      iex> Vtex.Focus.enable() =~ "1004h"
      true
  """
  @spec enable() :: binary()
  def enable, do: @enable

  @doc """
  The control sequence that disables focus reporting. Write it on teardown.

  ## Examples

      iex> Vtex.Focus.disable() =~ "1004l"
      true
  """
  @spec disable() :: binary()
  def disable, do: @disable
end
