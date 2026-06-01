defmodule Vtex.Output.ANSI do
  @moduledoc """
  A drop-in superset of Elixir's `IO.ANSI`.

  Every `IO.ANSI` function is exposed here — the unchanged ones simply
  **delegate** to `IO.ANSI`, so parity is guaranteed by construction rather than
  asserted by hand. You can swap `IO.ANSI` for `Vtex.Output.ANSI` and keep the
  same calls: `Vtex.Output.ANSI.red()`, `Vtex.Output.ANSI.cursor(2, 3)`,
  `Vtex.Output.ANSI.format([:red, "hi"])`.

  On top of that it adds what `IO.ANSI` cannot express — notably **24-bit
  truecolor** via `true_color/3` and `true_color_background/3`. Richer screen and
  cursor control (alternate buffer, scroll regions, save/restore, hide/show)
  lives in `Vtex.Output.Screen` and `Vtex.Output.Cursor`; mouse/paste/focus toggles in
  `Vtex.Mouse`, `Vtex.Paste`, `Vtex.Focus`.

  Like the rest of Vtex, every function returns iodata for you to write; nothing
  here performs IO.

  ## Differences from `IO.ANSI`

  These are the only functions that *don't* delegate, because Vtex intentionally
  diverges:

    * `enabled?/0` is always `true` — you call this module specifically to
      produce sequences for a terminal.
    * `format/1` and `format_fragment/1` **emit by default** (`emit? = true`),
      whereas `IO.ANSI` defaults to `enabled?/0` (off unless configured). Pass an
      explicit boolean as the second argument to override.
    * `true_color/3` and `true_color_background/3` have no `IO.ANSI` equivalent.
  """

  # Atom → escape-sequence map, derived at compile time from IO.ANSI's own
  # 0-arity sequence functions, so the codes are never re-listed here. Boolean
  # (`enabled?`) and non-binary (`syntax_colors`) functions are filtered out.
  @io_ansi_atoms (for {name, 0} <- IO.ANSI.__info__(:functions),
                      seq = apply(IO.ANSI, name, []),
                      is_binary(seq),
                      into: %{},
                      do: {name, seq})

  # The cursor moves also have a 1-arity form, so they're delegated explicitly
  # below rather than in the 0-arity loop.
  @cursor_moves [:cursor_up, :cursor_down, :cursor_left, :cursor_right]

  # Delegate every named 0-arity sequence (red/0, bright/0, clear/0, …) to
  # IO.ANSI. Docs/specs are kept so the public surface stays self-describing.
  for {name, seq} <- Enum.sort(@io_ansi_atoms), name not in @cursor_moves do
    @doc "Returns `#{inspect(seq)}`. Delegates to `IO.ANSI.#{name}/0`."
    @spec unquote(name)() :: binary()
    defdelegate unquote(name)(), to: IO.ANSI
  end

  @doc "Whether ANSI output should be emitted. Always `true` for Vtex."
  @spec enabled?() :: boolean()
  def enabled?, do: true

  @doc """
  Move the cursor to `line`, `column` (1-based). Mirrors `IO.ANSI.cursor/2`.
  """
  @spec cursor(integer(), integer()) :: binary()
  defdelegate cursor(line, column), to: IO.ANSI

  @doc "Move the cursor up `n` lines (default 1). Mirrors `IO.ANSI.cursor_up/1`."
  @spec cursor_up() :: binary()
  @spec cursor_up(integer()) :: binary()
  defdelegate cursor_up(), to: IO.ANSI
  defdelegate cursor_up(n), to: IO.ANSI

  @doc "Move the cursor down `n` lines (default 1). Mirrors `IO.ANSI.cursor_down/1`."
  @spec cursor_down() :: binary()
  @spec cursor_down(integer()) :: binary()
  defdelegate cursor_down(), to: IO.ANSI
  defdelegate cursor_down(n), to: IO.ANSI

  @doc "Move the cursor right `n` columns (default 1). Mirrors `IO.ANSI.cursor_right/1`."
  @spec cursor_right() :: binary()
  @spec cursor_right(integer()) :: binary()
  defdelegate cursor_right(), to: IO.ANSI
  defdelegate cursor_right(n), to: IO.ANSI

  @doc "Move the cursor left `n` columns (default 1). Mirrors `IO.ANSI.cursor_left/1`."
  @spec cursor_left() :: binary()
  @spec cursor_left(integer()) :: binary()
  defdelegate cursor_left(), to: IO.ANSI
  defdelegate cursor_left(n), to: IO.ANSI

  @doc """
  256-colour foreground: a palette index (`color/1`) or a 6×6×6 cube point
  (`color/3`, each component 0..5). Delegates to `IO.ANSI`.

  ## Examples

      iex> Vtex.Output.ANSI.color(196)
      "\\e[38;5;196m"

      iex> Vtex.Output.ANSI.color(5, 0, 0)
      "\\e[38;5;196m"
  """
  @spec color(0..255) :: binary()
  defdelegate color(code), to: IO.ANSI

  @spec color(0..5, 0..5, 0..5) :: binary()
  defdelegate color(r, g, b), to: IO.ANSI

  @doc "256-colour background; see `color/1` and `color/3`. Delegates to `IO.ANSI`."
  @spec color_background(0..255) :: binary()
  defdelegate color_background(code), to: IO.ANSI

  @spec color_background(0..5, 0..5, 0..5) :: binary()
  defdelegate color_background(r, g, b), to: IO.ANSI

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
  emitted. Mirrors `IO.ANSI.format/2`, but `emit?` defaults to `true` — you call
  this module specifically to produce sequences for a terminal.

  ## Examples

      iex> Vtex.Output.ANSI.format([:red, :bright, "hi"]) |> IO.iodata_to_binary()
      "\\e[31m\\e[1mhi\\e[0m"

      iex> Vtex.Output.ANSI.format([:red, "hi"], false) |> IO.iodata_to_binary()
      "hi"
  """
  @spec format(IO.chardata(), boolean()) :: IO.chardata()
  def format(chardata, emit? \\ true), do: IO.ANSI.format(chardata, emit?)

  @doc """
  Like `format/2`, but never appends a trailing reset. Mirrors
  `IO.ANSI.format_fragment/2`, with `emit?` defaulting to `true`.
  """
  @spec format_fragment(IO.chardata(), boolean()) :: IO.chardata()
  def format_fragment(chardata, emit? \\ true), do: IO.ANSI.format_fragment(chardata, emit?)
end
