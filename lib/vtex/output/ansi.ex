defmodule Vtex.Output.ANSI do
  @moduledoc """
  A drop-in superset of Elixir's `IO.ANSI`.

  Every `IO.ANSI` function is mirrored here byte-for-byte — the test suite
  asserts parity against `IO.ANSI` itself — so you can swap `IO.ANSI` for
  `Vtex.Output.ANSI` and keep the same calls: `Vtex.Output.ANSI.red()`,
  `Vtex.Output.ANSI.cursor(2, 3)`, `Vtex.Output.ANSI.format([:red, "hi"])`.

  On top of that it adds what `IO.ANSI` cannot express — notably **24-bit
  truecolor** via `true_color/3` and `true_color_background/3`. Richer screen and
  cursor control (alternate buffer, scroll regions, save/restore, hide/show)
  lives in `Vtex.Output.Screen` and `Vtex.Output.Cursor`; mouse/paste/focus toggles in
  `Vtex.Mouse`, `Vtex.Paste`, `Vtex.Focus`.

  Like the rest of Vtex, every function returns iodata for you to write; nothing
  here performs IO.

  ## Difference from `IO.ANSI`

  `format/1` and `format_fragment/1` **emit by default** (`emit? = true`),
  because you call this module specifically to produce sequences for a terminal.
  (`IO.ANSI` instead defaults to `enabled?/0`, which is off unless configured.)
  Pass an explicit boolean as the second argument to override.
  """

  # SGR named attributes, with the exact codes IO.ANSI uses.
  @sgr_codes [
    reset: 0,
    bright: 1,
    faint: 2,
    italic: 3,
    underline: 4,
    blink_slow: 5,
    blink_rapid: 6,
    inverse: 7,
    reverse: 7,
    conceal: 8,
    crossed_out: 9,
    primary_font: 10,
    font_1: 11,
    font_2: 12,
    font_3: 13,
    font_4: 14,
    font_5: 15,
    font_6: 16,
    font_7: 17,
    font_8: 18,
    font_9: 19,
    normal: 22,
    not_italic: 23,
    no_underline: 24,
    blink_off: 25,
    inverse_off: 27,
    reverse_off: 27,
    framed: 51,
    encircled: 52,
    overlined: 53,
    not_framed_encircled: 54,
    not_overlined: 55,
    black: 30,
    red: 31,
    green: 32,
    yellow: 33,
    blue: 34,
    magenta: 35,
    cyan: 36,
    white: 37,
    default_color: 39,
    light_black: 90,
    light_red: 91,
    light_green: 92,
    light_yellow: 93,
    light_blue: 94,
    light_magenta: 95,
    light_cyan: 96,
    light_white: 97,
    black_background: 40,
    red_background: 41,
    green_background: 42,
    yellow_background: 43,
    blue_background: 44,
    magenta_background: 45,
    cyan_background: 46,
    white_background: 47,
    default_background: 49,
    light_black_background: 100,
    light_red_background: 101,
    light_green_background: 102,
    light_yellow_background: 103,
    light_blue_background: 104,
    light_magenta_background: 105,
    light_cyan_background: 106,
    light_white_background: 107
  ]

  @non_sgr %{home: "\e[H", clear: "\e[2J", clear_line: "\e[2K"}

  @sequences @sgr_codes
             |> Enum.into(%{}, fn {name, code} -> {name, "\e[#{code}m"} end)
             |> Map.merge(@non_sgr)

  # Atoms accepted by format/1 — the 0-arity sequences plus the default cursor moves.
  @format_atoms Map.merge(@sequences, %{
                  cursor_up: "\e[1A",
                  cursor_down: "\e[1B",
                  cursor_left: "\e[1D",
                  cursor_right: "\e[1C"
                })

  # Generate the named sequence functions (red/0, bright/0, clear/0, …).
  for {name, seq} <- @sequences do
    @doc "Returns `#{inspect(seq)}`."
    @spec unquote(name)() :: binary()
    def unquote(name)(), do: unquote(seq)
  end

  @doc "Whether ANSI output should be emitted. Always `true` for Vtex."
  @spec enabled?() :: boolean()
  def enabled?, do: true

  @doc """
  Move the cursor to `line`, `column` (1-based). Mirrors `IO.ANSI.cursor/2`.
  """
  @spec cursor(integer(), integer()) :: binary()
  def cursor(line, column), do: "\e[#{line};#{column}H"

  @doc "Move the cursor up `n` lines (default 1)."
  @spec cursor_up(integer()) :: binary()
  def cursor_up(n \\ 1), do: "\e[#{n}A"

  @doc "Move the cursor down `n` lines (default 1)."
  @spec cursor_down(integer()) :: binary()
  def cursor_down(n \\ 1), do: "\e[#{n}B"

  @doc "Move the cursor right `n` columns (default 1)."
  @spec cursor_right(integer()) :: binary()
  def cursor_right(n \\ 1), do: "\e[#{n}C"

  @doc "Move the cursor left `n` columns (default 1)."
  @spec cursor_left(integer()) :: binary()
  def cursor_left(n \\ 1), do: "\e[#{n}D"

  @doc """
  256-colour foreground: a palette index (`color/1`) or a 6×6×6 cube point
  (`color/3`, each component 0..5). Mirrors `IO.ANSI`.

  ## Examples

      iex> Vtex.Output.ANSI.color(196)
      "\\e[38;5;196m"

      iex> Vtex.Output.ANSI.color(5, 0, 0)
      "\\e[38;5;196m"
  """
  @spec color(0..255) :: binary()
  def color(code) when code in 0..255, do: "\e[38;5;#{code}m"

  @spec color(0..5, 0..5, 0..5) :: binary()
  def color(r, g, b) when r in 0..5 and g in 0..5 and b in 0..5,
    do: color(16 + 36 * r + 6 * g + b)

  @doc "256-colour background; see `color/1` and `color/3`."
  @spec color_background(0..255) :: binary()
  def color_background(code) when code in 0..255, do: "\e[48;5;#{code}m"

  @spec color_background(0..5, 0..5, 0..5) :: binary()
  def color_background(r, g, b) when r in 0..5 and g in 0..5 and b in 0..5,
    do: color_background(16 + 36 * r + 6 * g + b)

  @doc """
  24-bit truecolor foreground (each component 0..255). Not available in `IO.ANSI`.

  ## Examples

      iex> Vtex.Output.ANSI.true_color(255, 128, 0)
      "\\e[38;2;255;128;0m"
  """
  @spec true_color(0..255, 0..255, 0..255) :: binary()
  def true_color(r, g, b) when r in 0..255 and g in 0..255 and b in 0..255,
    do: "\e[38;2;#{r};#{g};#{b}m"

  @doc "24-bit truecolor background (each component 0..255). Not in `IO.ANSI`."
  @spec true_color_background(0..255, 0..255, 0..255) :: binary()
  def true_color_background(r, g, b) when r in 0..255 and g in 0..255 and b in 0..255,
    do: "\e[48;2;#{r};#{g};#{b}m"

  @doc """
  Format chardata with embedded ANSI atoms, appending a reset if anything was
  emitted. Mirrors `IO.ANSI.format/2`, but `emit?` defaults to `true`.

  ## Examples

      iex> Vtex.Output.ANSI.format([:red, :bright, "hi"]) |> IO.iodata_to_binary()
      "\\e[31m\\e[1mhi\\e[0m"

      iex> Vtex.Output.ANSI.format([:red, "hi"], false) |> IO.iodata_to_binary()
      "hi"
  """
  @spec format(IO.chardata(), boolean()) :: IO.chardata()
  def format(chardata, emit? \\ true) do
    {iodata, emitted?} = build(chardata, emit?)
    if emit? and emitted?, do: [iodata, "\e[0m"], else: iodata
  end

  @doc """
  Like `format/2`, but never appends a trailing reset. Mirrors
  `IO.ANSI.format_fragment/2`, with `emit?` defaulting to `true`.
  """
  @spec format_fragment(IO.chardata(), boolean()) :: IO.chardata()
  def format_fragment(chardata, emit? \\ true) do
    {iodata, _emitted?} = build(chardata, emit?)
    iodata
  end

  defp build(list, emit?) when is_list(list) do
    Enum.reduce(list, {[], false}, fn item, {acc, emitted?} ->
      {io, e} = build(item, emit?)
      {[acc, io], emitted? or e}
    end)
  end

  defp build(binary, _emit?) when is_binary(binary), do: {binary, false}
  defp build(int, _emit?) when is_integer(int), do: {int, false}

  defp build(atom, emit?) when is_atom(atom) do
    case Map.fetch(@format_atoms, atom) do
      {:ok, seq} -> {if(emit?, do: seq, else: []), emit?}
      :error -> raise ArgumentError, "invalid ANSI sequence specification: #{inspect(atom)}"
    end
  end
end
