defmodule Vtex.Input do
  @moduledoc """
  Maps raw tokens from `Vtex.Input.Tokenizer` to semantic input events.

  This is a pure, stateless interpretation layer, typically called on the tokens
  returned by `Vtex.Input.Stream.feed/2`. It understands the common key sequences sent
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
      {:alt, byte()}
      {:key, base_event, [:shift | :alt | :ctrl | :meta]}
      {:mouse, Vtex.Mouse.event()}
      :paste_start | :paste_end
      :focus_in | :focus_out
      {:cursor_position, row :: pos_integer(), col :: pos_integer()}
      {:char, char()}
      {:sgr, [Vtex.SGR.attribute()]}
      {:unknown, Vtex.Input.Tokenizer.token()}

  Arrow and editing keys are sent differently depending on the terminal's cursor
  key mode: as CSI (`ESC [ A`) in normal mode, or as SS3 (`ESC O A`) in
  application mode. Both forms are handled.

  ## Modified keys

  Holding `Shift`, `Ctrl` or `Alt` while pressing an arrow, navigation or
  function key produces a CSI sequence with a modifier parameter — `Shift+Up` is
  `CSI 1 ; 2 A`, `Ctrl+Home` is `CSI 1 ; 5 H`, `Shift+F5` is `CSI 15 ; 2 ~`. The
  modifier is encoded as `1 + bitmask`, where the bitmask is `1=Shift`, `2=Alt`,
  `4=Ctrl`, `8=Meta`.

  These surface as `{:key, base, mods}`, where `base` is the same event the
  unmodified key would produce (`:arrow_up`, `:home`, `{:function, 5}`) and
  `mods` is a list drawn from `:shift`, `:alt`, `:ctrl`, `:meta` in that order.
  Unmodified keys keep their plain form, so `:arrow_up` and `{:key, :arrow_up,
  [:shift]}` are distinct.

  ## Alt / Meta keys

  A terminal sends an `Alt`/`Meta`-modified key as an `ESC` prefix followed by
  the key (xterm's `metaSendsEscape`), so `Alt+a` arrives as `ESC a`. These
  surface as `{:alt, byte}` events, where `byte` is the key that followed `ESC`.

  This collides with the standalone `Escape` key, which is a bare `ESC` with
  nothing after it. Because the parser is stateless and timeout-free it cannot
  tell "the user pressed Escape" from "an `ESC`-prefixed sequence is still
  arriving": a lone trailing `ESC` is held in the `Vtex.Input.Stream` buffer until the
  next byte decides it, and `ESC` immediately followed by a key reads as `:alt`.
  Disambiguating a real `Escape` press requires an inactivity timeout in the
  caller (flush as `:escape` if no byte follows within a few milliseconds);
  Vtex deliberately leaves that policy to you.

  ## Bracketed paste

  When bracketed paste is enabled (`Vtex.Mouse`-style, via `Vtex.Paste.enable/0`)
  the terminal wraps pasted text between `ESC [ 200 ~` and `ESC [ 201 ~`, which
  surface as `:paste_start` and `:paste_end`. The pasted bytes in between arrive
  as ordinary events — accumulate them until `:paste_end` to reconstruct the
  text, treating it as literal data (e.g. an embedded `:enter` is a newline in
  the pasted content, not a "submit"). Apply your own size limit while
  accumulating: the parser is stateless and does not buffer the paste for you,
  so a never-terminated paste cannot exhaust memory.

  ## Reports and focus

  A couple of sequences arrive as replies to a query you send, or when a mode is
  enabled:

    * A **Cursor Position Report** (`CSI <row> ; <col> R`, the reply to writing
      `CSI 6 n`) becomes `{:cursor_position, row, col}` (1-based). This is the
      in-band way to read the cursor — and, by parking it at `CSI 999 ; 999 H`
      first, to probe the terminal size when the transport can't tell you
      (prefer SSH window-change / Telnet NAWS when it can).
    * **Focus reporting** (enabled with `Vtex.Focus.enable/0`) delivers
      `:focus_in` and `:focus_out` as the window gains and loses focus.
  """

  import Bitwise, only: [&&&: 2]

  alias Vtex.{Mouse, SGR}
  alias Vtex.Input.Tokenizer

  @type modifier :: :shift | :alt | :ctrl | :meta

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
          | {:alt, byte()}
          | {:key, event(), [modifier()]}
          | {:mouse, Mouse.event()}
          | :paste_start
          | :paste_end
          | :focus_in
          | :focus_out
          | {:cursor_position, pos_integer(), pos_integer()}
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

      iex> Vtex.Input.interpret([{:csi, "", "", ?A}, {:ss3, ?B}])
      [:arrow_up, :arrow_down]

      iex> Vtex.Input.interpret([{:csi, "5", "", ?~}])
      [:page_up]

      iex> Vtex.Input.interpret([{:esc, ?x}])
      [{:alt, ?x}]

      iex> Vtex.Input.interpret([{:csi, "1;2", "", ?A}, {:csi, "15;5", "", ?~}])
      [{:key, :arrow_up, [:shift]}, {:key, {:function, 5}, [:ctrl]}]

      iex> Vtex.Input.interpret([{:csi, "0;10;5", "<", ?M}])
      [{:mouse, %{action: :press, button: :left, x: 10, y: 5, mods: []}}]

      iex> Vtex.Input.interpret([{:csi, "200", "", ?~}, {:text, "hi"}, {:csi, "201", "", ?~}])
      [:paste_start, {:char, ?h}, {:char, ?i}, :paste_end]

      iex> Vtex.Input.interpret([{:csi, "24;80", "", ?R}, {:csi, "", "", ?O}])
      [{:cursor_position, 24, 80}, :focus_out]
  """
  @spec interpret([Tokenizer.token()]) :: [event()]
  def interpret(tokens) when is_list(tokens) do
    Enum.flat_map(tokens, &interpret_token/1)
  end

  # Text expands to one event per character.
  defp interpret_token({:text, bytes}), do: interpret_text(bytes, [])

  # CSI cursor / editing keys (no parameters, no intermediates).
  defp interpret_token({:csi, "", "", final}) when final in [?A, ?B, ?C, ?D, ?H, ?F],
    do: [csi_final(final)]

  # Modified cursor / navigation keys — CSI 1 ; <mod> <final>.
  defp interpret_token({:csi, "1;" <> mod, "", final} = token)
       when final in [?A, ?B, ?C, ?D, ?H, ?F],
       do: modified(csi_final(final), mod, token)

  # Focus reporting — CSI I / CSI O (mode 1004; see Vtex.Focus).
  defp interpret_token({:csi, "", "", ?I}), do: [:focus_in]
  defp interpret_token({:csi, "", "", ?O}), do: [:focus_out]

  # Cursor Position Report — CSI <row> ; <col> R (reply to CSI 6 n).
  defp interpret_token({:csi, params, "", ?R} = token) do
    case two_ints(params) do
      {row, col} -> [{:cursor_position, row, col}]
      nil -> [{:unknown, token}]
    end
  end

  # SGR mouse events — CSI < b ; x ; y M/m (the '<' marker lands in intermediates).
  defp interpret_token({:csi, params, "<", final} = token) when final in [?M, ?m] do
    case Mouse.decode(params, final) do
      nil -> [{:unknown, token}]
      event -> [{:mouse, event}]
    end
  end

  # SGR — colour / style.
  defp interpret_token({:csi, params, "", ?m}), do: [{:sgr, SGR.parse(params)}]

  # Bracketed paste markers — CSI 200 ~ / CSI 201 ~ (see Vtex.Paste).
  defp interpret_token({:csi, "200", "", ?~}), do: [:paste_start]
  defp interpret_token({:csi, "201", "", ?~}), do: [:paste_end]

  # Tilde-terminated editing and function keys — CSI <n> ~ or CSI <n> ; <mod> ~.
  defp interpret_token({:csi, params, "", ?~} = token) do
    case String.split(params, ";") do
      [n] ->
        case tilde_key(n) do
          nil -> [{:unknown, token}]
          event -> [event]
        end

      [n, mod] ->
        case tilde_key(n) do
          nil -> [{:unknown, token}]
          base -> modified(base, mod, token)
        end

      _ ->
        [{:unknown, token}]
    end
  end

  defp interpret_token({:csi, _params, _inter, _final} = token), do: [{:unknown, token}]

  # ESC + byte — an Alt/Meta-modified key (xterm "metaSendsEscape"). See the
  # moduledoc for the standalone-Escape ambiguity this implies.
  defp interpret_token({:esc, byte}), do: [{:alt, byte}]

  # SS3 — application-mode cursor keys and F1-F4.
  defp interpret_token({:ss3, byte} = token) do
    case ss3(byte) do
      nil -> [{:unknown, token}]
      event -> [event]
    end
  end

  defp interpret_token(token), do: [{:unknown, token}]

  # Parse a "<a>;<b>" parameter pair into {a, b}, or nil if malformed.
  defp two_ints(params) do
    case params |> String.split(";") |> Enum.map(&Integer.parse/1) do
      [{a, ""}, {b, ""}] -> {a, b}
      _ -> nil
    end
  end

  # --- modifier decoding ---

  # Wrap a base key event with its modifier list, or pass the token through if
  # the modifier parameter is unrecognised.
  defp modified(base, mod, token) do
    case modifiers(mod) do
      [] -> [{:unknown, token}]
      mods -> [{:key, base, mods}]
    end
  end

  # The xterm modifier parameter is `1 + bitmask` (1=Shift, 2=Alt, 4=Ctrl,
  # 8=Meta). Returns the modifiers in a stable order, or [] if unrecognised.
  defp modifiers(param) do
    case Integer.parse(param) do
      {n, ""} when n >= 1 ->
        bits = n - 1

        for {bit, name} <- [{1, :shift}, {2, :alt}, {4, :ctrl}, {8, :meta}],
            (bits &&& bit) != 0,
            do: name

      _ ->
        []
    end
  end

  # --- text byte interpretation ---
  #
  # A leading ESC reaches this path only via `Vtex.Input.Stream.flush/1`, which is how
  # a standalone Escape keypress is resolved (see that module's docs).

  defp interpret_text(<<>>, acc), do: Enum.reverse(acc)
  defp interpret_text(<<?\r, rest::binary>>, acc), do: interpret_text(rest, [:enter | acc])
  defp interpret_text(<<?\n, rest::binary>>, acc), do: interpret_text(rest, [:enter | acc])
  defp interpret_text(<<?\t, rest::binary>>, acc), do: interpret_text(rest, [:tab | acc])
  defp interpret_text(<<0x7F, rest::binary>>, acc), do: interpret_text(rest, [:backspace | acc])
  defp interpret_text(<<0x08, rest::binary>>, acc), do: interpret_text(rest, [:backspace | acc])
  defp interpret_text(<<0x1B, rest::binary>>, acc), do: interpret_text(rest, [:escape | acc])

  defp interpret_text(<<cp::utf8, rest::binary>>, acc),
    do: interpret_text(rest, [{:char, cp} | acc])

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
