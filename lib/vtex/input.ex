defmodule Vtex.Input do
  @moduledoc """
  Maps raw tokens from `Vtex.Tokenizer` to semantic input events.

  This is a pure, stateless interpretation layer, typically called on the tokens
  returned by `Vtex.Stream.feed/2`. It understands the common key sequences sent
  by terminals (arrow keys, editing keys, function keys) regardless of whether
  they arrive as CSI or SS3, and it expands runs of text into per-character
  events, decoding UTF-8 so multi-byte characters stay whole.

  ## Event types

      :enter
      :backspace
      :escape
      :tab
      :arrow_up | :arrow_down | :arrow_left | :arrow_right
      :insert | :delete | :home | :end | :page_up | :page_down
      {:function, 1..12}
      {:char, char()}
      {:sgr, [Vtex.SGR.attribute()]}
      {:unknown, Vtex.Tokenizer.token()}

  Arrow and editing keys are sent differently depending on the terminal's cursor
  key mode: as CSI (`ESC [ A`) in normal mode, or as SS3 (`ESC O A`) in
  application mode. Both forms are handled.
  """

  alias Vtex.{SGR, Tokenizer}

  @type event ::
          :enter
          | :backspace
          | :escape
          | :tab
          | :arrow_up
          | :arrow_down
          | :arrow_left
          | :arrow_right
          | :insert
          | :delete
          | :home
          | :end
          | :page_up
          | :page_down
          | {:function, 1..12}
          | {:char, char()}
          | {:sgr, [SGR.attribute()]}
          | {:unknown, Tokenizer.token()}

  @doc """
  Interpret a list of tokens into a list of semantic events.

  ## Examples

      iex> Vtex.Input.interpret([{:text, "hi\\r"}])
      [{:char, ?h}, {:char, ?i}, :enter]

      iex> Vtex.Input.interpret([{:text, "é"}])
      [{:char, ?é}]

      iex> Vtex.Input.interpret([{:csi, "", ?A}, {:ss3, ?B}])
      [:arrow_up, :arrow_down]

      iex> Vtex.Input.interpret([{:csi, "5", ?~}])
      [:page_up]
  """
  @spec interpret([Tokenizer.token()]) :: [event()]
  def interpret(tokens) when is_list(tokens) do
    Enum.flat_map(tokens, &interpret_token/1)
  end

  # Text expands to one event per character.
  defp interpret_token({:text, bytes}), do: interpret_text(bytes, [])

  # CSI cursor / editing keys (no parameters).
  defp interpret_token({:csi, "", final}) when final in [?A, ?B, ?C, ?D, ?H, ?F],
    do: [csi_final(final)]

  # SGR — colour / style.
  defp interpret_token({:csi, params, ?m}), do: [{:sgr, SGR.parse(params)}]

  # Tilde-terminated editing and function keys (CSI <n> ~).
  defp interpret_token({:csi, params, ?~} = token) do
    case tilde_key(params) do
      nil -> [{:unknown, token}]
      event -> [event]
    end
  end

  defp interpret_token({:csi, _params, _final} = token), do: [{:unknown, token}]

  # SS3 — application-mode cursor keys and F1-F4.
  defp interpret_token({:ss3, byte} = token) do
    case ss3(byte) do
      nil -> [{:unknown, token}]
      event -> [event]
    end
  end

  defp interpret_token(token), do: [{:unknown, token}]

  # --- text byte interpretation ---

  defp interpret_text(<<>>, acc), do: Enum.reverse(acc)
  defp interpret_text(<<?\r, rest::binary>>, acc), do: interpret_text(rest, [:enter | acc])
  defp interpret_text(<<?\n, rest::binary>>, acc), do: interpret_text(rest, [:enter | acc])
  defp interpret_text(<<?\t, rest::binary>>, acc), do: interpret_text(rest, [:tab | acc])
  defp interpret_text(<<0x7F, rest::binary>>, acc), do: interpret_text(rest, [:backspace | acc])
  defp interpret_text(<<0x08, rest::binary>>, acc), do: interpret_text(rest, [:backspace | acc])
  defp interpret_text(<<0x1B, rest::binary>>, acc), do: interpret_text(rest, [:escape | acc])
  defp interpret_text(<<cp::utf8, rest::binary>>, acc), do: interpret_text(rest, [{:char, cp} | acc])
  # A byte that isn't valid UTF-8 — emit it raw so nothing is silently dropped.
  defp interpret_text(<<b, rest::binary>>, acc), do: interpret_text(rest, [{:char, b} | acc])

  # --- key tables ---

  defp csi_final(?A), do: :arrow_up
  defp csi_final(?B), do: :arrow_down
  defp csi_final(?C), do: :arrow_right
  defp csi_final(?D), do: :arrow_left
  defp csi_final(?H), do: :home
  defp csi_final(?F), do: :end

  defp ss3(?A), do: :arrow_up
  defp ss3(?B), do: :arrow_down
  defp ss3(?C), do: :arrow_right
  defp ss3(?D), do: :arrow_left
  defp ss3(?H), do: :home
  defp ss3(?F), do: :end
  defp ss3(?P), do: {:function, 1}
  defp ss3(?Q), do: {:function, 2}
  defp ss3(?R), do: {:function, 3}
  defp ss3(?S), do: {:function, 4}
  defp ss3(_), do: nil

  # xterm-style "CSI <n> ~" sequences.
  defp tilde_key("1"), do: :home
  defp tilde_key("2"), do: :insert
  defp tilde_key("3"), do: :delete
  defp tilde_key("4"), do: :end
  defp tilde_key("5"), do: :page_up
  defp tilde_key("6"), do: :page_down
  defp tilde_key("7"), do: :home
  defp tilde_key("8"), do: :end
  defp tilde_key("11"), do: {:function, 1}
  defp tilde_key("12"), do: {:function, 2}
  defp tilde_key("13"), do: {:function, 3}
  defp tilde_key("14"), do: {:function, 4}
  defp tilde_key("15"), do: {:function, 5}
  defp tilde_key("17"), do: {:function, 6}
  defp tilde_key("18"), do: {:function, 7}
  defp tilde_key("19"), do: {:function, 8}
  defp tilde_key("20"), do: {:function, 9}
  defp tilde_key("21"), do: {:function, 10}
  defp tilde_key("23"), do: {:function, 11}
  defp tilde_key("24"), do: {:function, 12}
  defp tilde_key(_), do: nil
end
