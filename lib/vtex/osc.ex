defmodule Vtex.OSC do
  @moduledoc """
  Operating System Command output sequences: window title and hyperlinks.

  These are the OSC counterparts to the CSI output in `Vtex.Cursor` / `Vtex.Screen`,
  and like everything else in Vtex they return iodata for you to write.

  OSC sequences end with a String Terminator; these use `BEL` (`0x07`), the form
  every common terminal accepts.
  """

  @bel "\a"

  @doc """
  Set the terminal window (and icon) title. Mirrors xterm's `OSC 0`.

  ## Examples

      iex> Vtex.OSC.title("My BBS")
      "\\e]0;My BBS\\a"
  """
  @spec title(String.t()) :: binary()
  def title(text) when is_binary(text), do: "\e]0;" <> text <> @bel

  @doc """
  Build a clickable hyperlink (`OSC 8`): `text` that links to `url`.

  Terminals that support it render `text` as a link; others just show `text`.

  ## Examples

      iex> Vtex.OSC.hyperlink("Anthropic", "https://anthropic.com")
      "\\e]8;;https://anthropic.com\\aAnthropic\\e]8;;\\a"
  """
  @spec hyperlink(String.t(), String.t()) :: binary()
  def hyperlink(text, url) when is_binary(text) and is_binary(url) do
    "\e]8;;" <> url <> @bel <> text <> "\e]8;;" <> @bel
  end
end
