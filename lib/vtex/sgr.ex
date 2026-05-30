defmodule Vtex.SGR do
  @moduledoc """
  SGR (Select Graphic Rendition) colour and text-style attributes, both ways.

  SGR is the `m`-terminated CSI sequence that carries colour and text-style
  information (`ESC [ 1 ; 31 m` = bold red, for example). `parse/1` turns the raw
  parameter binary into a list of structured attributes; `encode/1` turns a list
  of attributes back into a sequence ready to write — including 256-colour and
  truecolor, which `IO.ANSI` does not cover.

  `parse/1` is used internally by `Vtex.Input`; both functions are useful
  standalone.

  ## Attribute types

      :reset
      :bold | :faint | :italic | :underline | :blink | :inverse
      {:fg, color()}
      {:bg, color()}
      {:unknown, integer()}   # a recognised-as-numeric but unmapped code

  where `color()` is one of:

      :black | :red | :green | :yellow | :blue | :magenta | :cyan | :white
      {:bright, basic_color()}   # codes 90-97 / 100-107
      {:index, 0..255}           # 256-colour palette (38;5;n / 48;5;n)
      {:rgb, 0..255, 0..255, 0..255}   # truecolor (38;2;r;g;b / 48;2;r;g;b)
  """

  @type basic_color ::
          :black | :red | :green | :yellow | :blue | :magenta | :cyan | :white

  @type color ::
          basic_color()
          | {:bright, basic_color()}
          | {:index, 0..255}
          | {:rgb, 0..255, 0..255, 0..255}

  @type attribute ::
          :reset
          | :bold
          | :faint
          | :italic
          | :underline
          | :blink
          | :inverse
          | {:fg, color()}
          | {:bg, color()}
          | {:unknown, integer()}

  @doc """
  Parse an SGR parameter binary into a list of attributes.

  An empty parameter string is treated as `:reset` (a bare `ESC [ m`), matching
  terminal behaviour. Non-numeric parameters are ignored.

  ## Examples

      iex> Vtex.SGR.parse("0")
      [:reset]

      iex> Vtex.SGR.parse("")
      [:reset]

      iex> Vtex.SGR.parse("1;31")
      [:bold, {:fg, :red}]

      iex> Vtex.SGR.parse("38;5;200")
      [{:fg, {:index, 200}}]

      iex> Vtex.SGR.parse("48;2;10;20;30")
      [{:bg, {:rgb, 10, 20, 30}}]
  """
  @spec parse(binary()) :: [attribute()]
  def parse(params) when is_binary(params) do
    params
    |> split_params()
    |> to_attributes([])
  end

  @doc """
  Encode a list of attributes into an SGR control sequence (`ESC [ … m`).

  The inverse of `parse/1`: it accepts the same attribute terms — including
  256-colour (`{:index, n}`) and truecolor (`{:rgb, r, g, b}`) selectors that
  `IO.ANSI` does not cover. Write the result to the terminal.

  ## Examples

      iex> Vtex.SGR.encode([:bold, {:fg, :red}])
      "\\e[1;31m"

      iex> Vtex.SGR.encode([{:fg, {:rgb, 10, 20, 30}}, {:bg, {:index, 200}}])
      "\\e[38;2;10;20;30;48;5;200m"

      iex> Vtex.SGR.encode([:reset])
      "\\e[0m"
  """
  @spec encode([attribute()]) :: binary()
  def encode(attributes) when is_list(attributes) do
    "\e[" <> Enum.map_join(attributes, ";", &code/1) <> "m"
  end

  # An empty binary means "no parameters", which for SGR defaults to reset.
  defp split_params(""), do: [0]

  defp split_params(params) do
    params
    |> :binary.split(";", [:global])
    |> Enum.flat_map(fn
      "" -> [0]
      s -> parse_int(s)
    end)
  end

  defp parse_int(s) do
    case Integer.parse(s) do
      {n, ""} -> [n]
      _ -> []
    end
  end

  defp to_attributes([], acc), do: Enum.reverse(acc)

  # Extended colour selectors consume several parameters at once.
  defp to_attributes([38, 5, n | rest], acc),
    do: to_attributes(rest, [{:fg, {:index, n}} | acc])

  defp to_attributes([38, 2, r, g, b | rest], acc),
    do: to_attributes(rest, [{:fg, {:rgb, r, g, b}} | acc])

  defp to_attributes([48, 5, n | rest], acc),
    do: to_attributes(rest, [{:bg, {:index, n}} | acc])

  defp to_attributes([48, 2, r, g, b | rest], acc),
    do: to_attributes(rest, [{:bg, {:rgb, r, g, b}} | acc])

  defp to_attributes([code | rest], acc),
    do: to_attributes(rest, [attribute(code) | acc])

  defp attribute(0), do: :reset
  defp attribute(1), do: :bold
  defp attribute(2), do: :faint
  defp attribute(3), do: :italic
  defp attribute(4), do: :underline
  defp attribute(5), do: :blink
  defp attribute(7), do: :inverse
  defp attribute(c) when c in 30..37, do: {:fg, color(c - 30)}
  defp attribute(c) when c in 40..47, do: {:bg, color(c - 40)}
  defp attribute(c) when c in 90..97, do: {:fg, {:bright, color(c - 90)}}
  defp attribute(c) when c in 100..107, do: {:bg, {:bright, color(c - 100)}}
  defp attribute(c), do: {:unknown, c}

  @basic_colors [:black, :red, :green, :yellow, :blue, :magenta, :cyan, :white]

  defp color(n), do: Enum.at(@basic_colors, n)

  # --- encoding (attributes -> SGR sequence) ---

  defp code(:reset), do: "0"
  defp code(:bold), do: "1"
  defp code(:faint), do: "2"
  defp code(:italic), do: "3"
  defp code(:underline), do: "4"
  defp code(:blink), do: "5"
  defp code(:inverse), do: "7"
  defp code({:fg, c}), do: color_code(c, 30, 90, 38)
  defp code({:bg, c}), do: color_code(c, 40, 100, 48)
  defp code({:unknown, n}), do: Integer.to_string(n)

  defp color_code({:bright, name}, _base, bright, _ext),
    do: Integer.to_string(bright + color_index(name))

  defp color_code({:index, n}, _base, _bright, ext), do: "#{ext};5;#{n}"
  defp color_code({:rgb, r, g, b}, _base, _bright, ext), do: "#{ext};2;#{r};#{g};#{b}"
  defp color_code(name, base, _bright, _ext), do: Integer.to_string(base + color_index(name))

  defp color_index(name), do: Enum.find_index(@basic_colors, &(&1 == name))
end
