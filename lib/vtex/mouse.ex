defmodule Vtex.Mouse do
  @moduledoc """
  SGR mouse-reporting support: the control sequences that turn reporting on and
  off, and a decoder for the events the terminal sends back.

  Mouse reporting is opt-in. Write `enable/1` to the terminal to start receiving
  events and `disable/0` (on teardown) to stop. While enabled, the terminal
  sends each event as an SGR mouse sequence — `CSI < b ; x ; y M` for a
  press/motion or `… m` for a release — which `Vtex.Input` surfaces as a
  `{:mouse, event}` tuple. How much motion is reported depends on the `:motion`
  level passed to `enable/1`.

  Only the SGR encoding (mode 1006) is supported. It is the modern default and,
  unlike the legacy X10 encoding, is unambiguous and unbounded in coordinate
  range. Do **not** enable X10 mouse mode (`CSI ? 1000 h` *without* 1006): its
  raw coordinate bytes are not representable as a control sequence and cannot be
  tokenized.

  `enable/1` and `disable/0` are the one place this otherwise input-only library
  emits output, because mouse reporting cannot be received without first being
  switched on. They return the bytes for you to write; the library performs no
  IO of its own.

  ## Event

  A decoded event is a map:

      %{
        action: :press | :release | :drag | :move,
        button: :left | :middle | :right
               | :wheel_up | :wheel_down | :wheel_left | :wheel_right
               | :none | {:button, 8..11},
        x: pos_integer(),   # 1-based column
        y: pos_integer(),   # 1-based row
        mods: [:shift | :alt | :ctrl]
      }
  """

  import Bitwise, only: [&&&: 2]

  # SGR encoding (1006) is always on; the tracking mode varies by :motion level.
  @sgr "\e[?1006h"
  # disable turns off every mode we might have enabled, regardless of level.
  @disable "\e[?1006l\e[?1003l\e[?1002l\e[?1000l"

  @type button ::
          :left
          | :middle
          | :right
          | :wheel_up
          | :wheel_down
          | :wheel_left
          | :wheel_right
          | :none
          | {:button, 8..11}

  @type event :: %{
          action: :press | :release | :drag | :move,
          button: button(),
          x: pos_integer(),
          y: pos_integer(),
          mods: [:shift | :alt | :ctrl]
        }

  @doc """
  The control sequence that enables SGR mouse reporting. Write it to the terminal.

  The `:motion` option chooses how much motion is reported:

    * `:drag` (default) — press, release, and motion while a button is held
    * `:all` — also bare pointer motion with no button (fires on every cell the
      pointer crosses; a firehose, but needed for hover)
    * `:none` — press and release only

  ## Examples

      iex> Vtex.Mouse.enable() =~ "1002h"
      true

      iex> Vtex.Mouse.enable(motion: :all) =~ "1003h"
      true

      iex> Vtex.Mouse.enable(motion: :none) =~ "1002h"
      false
  """
  @spec enable(keyword()) :: binary()
  def enable(opts \\ []) do
    tracking =
      case Keyword.get(opts, :motion, :drag) do
        :none -> "\e[?1000h"
        :drag -> "\e[?1000h\e[?1002h"
        :all -> "\e[?1000h\e[?1003h"
      end

    tracking <> @sgr
  end

  @doc """
  The control sequence that disables mouse reporting. Write it on teardown.

  ## Examples

      iex> Vtex.Mouse.disable() =~ "1006l"
      true
  """
  @spec disable() :: binary()
  def disable, do: @disable

  @doc """
  Decode an SGR mouse sequence body into an event map, or `nil` if malformed.

  `params` is the CSI parameter string (`"b;x;y"`) and `final` is `?M`
  (press/motion) or `?m` (release).

  ## Examples

      iex> Vtex.Mouse.decode("0;10;5", ?M)
      %{action: :press, button: :left, x: 10, y: 5, mods: []}

      iex> Vtex.Mouse.decode("0;10;5", ?m)
      %{action: :release, button: :left, x: 10, y: 5, mods: []}

      iex> Vtex.Mouse.decode("64;3;3", ?M)
      %{action: :press, button: :wheel_up, x: 3, y: 3, mods: []}

      iex> Vtex.Mouse.decode("49;7;2", ?M)
      %{action: :drag, button: :middle, x: 7, y: 2, mods: [:ctrl]}
  """
  @spec decode(binary(), byte()) :: event() | nil
  def decode(params, final) when final in [?M, ?m] do
    case split_ints(params) do
      [cb, x, y] ->
        %{action: action(cb, final), button: button(cb), x: x, y: y, mods: mods(cb)}

      nil ->
        nil
    end
  end

  def decode(_params, _final), do: nil

  defp split_ints(params) do
    case params |> String.split(";") |> Enum.map(&Integer.parse/1) do
      [{a, ""}, {b, ""}, {c, ""}] -> [a, b, c]
      _ -> nil
    end
  end

  defp mods(cb) do
    for {bit, name} <- [{4, :shift}, {8, :alt}, {16, :ctrl}], (cb &&& bit) != 0, do: name
  end

  defp action(_cb, ?m), do: :release

  defp action(cb, ?M) do
    cond do
      (cb &&& 64) != 0 -> :press
      (cb &&& 32) == 0 -> :press
      (cb &&& 3) == 3 -> :move
      true -> :drag
    end
  end

  defp button(cb) do
    cond do
      (cb &&& 64) != 0 ->
        case cb &&& 3 do
          0 -> :wheel_up
          1 -> :wheel_down
          2 -> :wheel_left
          3 -> :wheel_right
        end

      (cb &&& 128) != 0 ->
        {:button, 8 + (cb &&& 3)}

      true ->
        case cb &&& 3 do
          0 -> :left
          1 -> :middle
          2 -> :right
          3 -> :none
        end
    end
  end
end
