defmodule Vtex.Input.Tokenizer do
  @moduledoc """
  Pure, stateless tokenizer for VT/ANSI escape sequences.

  Takes a binary and returns a list of typed tokens plus a leftover binary
  containing any trailing bytes that form an incomplete sequence. The leftover
  is meant to be prepended to the next chunk of input (see `Vtex.Input.Stream`).

  The tokenizer implements
  [Paul Williams' ANSI parser state machine](https://vt100.net/emu/dec_ansi_parser)
  as faithfully as a stateless tokenizer can. Within a control sequence it
  reproduces the `csi_entry` / `csi_param` / `csi_intermediate` / `csi_ignore`
  sub-states — parameter and intermediate bytes are collected into separate
  buffers, and a malformed ordering drops into `csi_ignore`, which swallows the
  rest of the sequence and emits nothing, exactly as the diagram specifies. It
  also honours the diagram's "anywhere" transitions: an `ESC` restarts parsing,
  `CAN`/`SUB` abort the sequence, other C0 controls are passed through (executed
  in place) while the sequence continues, and `DEL` is ignored. It has no state
  and no side effects, so it is fully testable with raw strings.

  A handful of details still differ from the reference parser — see
  "Deviations from the reference parser" below.

  ## Token types

      {:text, binary()}                          # run of printable / control bytes
      {:csi, params, intermediates, final}       # ESC [ <params> <intermediates> <final>
      {:ss3, byte()}                             # ESC O X
      {:osc, payload :: binary()}                # ESC ] ... ST
      {:esc, byte()}                             # ESC <other>
      {:invalid, binary()}                       # failed / rejected sequence

  For `:csi`, `params` and `intermediates` are binaries and `final` is a byte.
  For example `ESC [ ? 2 5 h` tokenizes to `{:csi, "25", "?", ?h}` — the private
  marker `?` lands in `intermediates`, the digits in `params`.

  Truncated sequences are never emitted as tokens; they are returned as the
  leftover binary so the caller can buffer them until more bytes arrive.

  ## Byte ranges

    * CSI parameter bytes: `0x30..0x39` and `;` — collected into `params`
    * CSI intermediate / private-marker bytes: `0x20..0x2F` and `0x3C..0x3F` —
      collected into `intermediates`
    * CSI final byte: `0x40..0x7E`
    * SS3: `ESC O <byte>` — always exactly three bytes
    * OSC: `ESC ] <payload> ST` where ST is `ESC \\` or `BEL` (`0x07`)

  `DCS`, `APC`, `PM` and `SOS` strings are recognised and immediately rejected
  as `{:invalid, ...}` — no game/BBS context needs them, and their unbounded
  payloads are a denial-of-service vector.

  ## Deviations from the reference parser

  This is a tokenizer, not a terminal, so a few parts of the diagram are
  intentionally absent or differ:

    * **The "anywhere" transitions are honoured only inside a CSI.** `ESC`,
      `CAN`, `SUB` and C0 controls get no special treatment inside OSC/string
      scanning or in the `escape` state itself — e.g. `ESC ESC` is emitted as a
      lone `{:esc, 0x1B}` rather than re-entering the escape state, and a stray
      control inside an OSC payload is copied verbatim.
    * **The diagram is 7-bit; colon is reserved.** Following the original
      diagram, a colon (`0x3A`) inside a CSI drops the sequence into
      `csi_ignore`. Terminals that use the ITU colon syntax for sub-parameters
      (e.g. `ESC [ 38 : 2 : r : g : b m`) will therefore have those sequences
      discarded — use the semicolon forms instead.
    * **No 8-bit C1 controls.** Only the 7-bit `ESC`-prefixed forms are
      recognised; bytes `0x80..0x9F` are treated as ordinary text, which is
      what UTF-8 continuation bytes require anyway. A `0x80..0xFF` byte appearing
      mid-CSI drops the sequence into `csi_ignore`.
    * **`DCS`, `APC`, `PM` and `SOS` are rejected, not parsed** (see above).
    * **OSC also accepts a `BEL` terminator**, an xterm extension the strict
      diagram does not include.
    * **Truncation defers C0 execution.** Because incomplete sequences are
      buffered as leftover, a C0 control arriving mid-sequence is not emitted
      until the sequence completes; the reference parser would execute it
      immediately.
  """

  @esc 0x1B
  @bel 0x07
  @can 0x18
  @sub 0x1A

  @type token ::
          {:text, binary()}
          | {:csi, binary(), binary(), byte()}
          | {:ss3, byte()}
          | {:osc, binary()}
          | {:esc, byte()}
          | {:invalid, binary()}

  @doc """
  Tokenize a binary into a list of tokens and a leftover binary.

  The leftover is the unconsumed tail when input ends mid-sequence. Pass it back
  prepended to the next chunk to resume parsing.

  ## Examples

      iex> Vtex.Input.Tokenizer.tokenize("hi")
      {[{:text, "hi"}], ""}

      iex> Vtex.Input.Tokenizer.tokenize(<<0x1B, ?[, ?A>>)
      {[{:csi, "", "", ?A}], ""}

      iex> Vtex.Input.Tokenizer.tokenize(<<0x1B, ?[, "?25h">>)
      {[{:csi, "25", "?", ?h}], ""}

      iex> Vtex.Input.Tokenizer.tokenize(<<?a, 0x1B, ?[>>)
      {[{:text, "a"}], <<0x1B, ?[>>}
  """
  @spec tokenize(binary()) :: {[token()], binary()}
  def tokenize(data) when is_binary(data), do: do_tokenize(data, [])

  defp do_tokenize(<<>>, acc), do: {Enum.reverse(acc), <<>>}

  defp do_tokenize(<<@esc, rest::binary>> = all, acc) do
    case parse_escape(rest) do
      {:ok, tokens, remaining} -> do_tokenize(remaining, Enum.reverse(tokens, acc))
      :incomplete -> {Enum.reverse(acc), all}
    end
  end

  defp do_tokenize(data, acc) do
    {text, rest} = take_text(data, <<>>)
    do_tokenize(rest, [{:text, text} | acc])
  end

  # Accumulate bytes until the next ESC (or end of input).
  defp take_text(<<@esc, _::binary>> = rest, acc), do: {acc, rest}
  defp take_text(<<>>, acc), do: {acc, <<>>}
  defp take_text(<<b, rest::binary>>, acc), do: take_text(rest, <<acc::binary, b>>)

  # --- escape dispatch (bytes following the leading ESC) ---

  defp parse_escape(<<>>), do: :incomplete

  # CSI — ESC [
  defp parse_escape(<<?[, rest::binary>>), do: parse_csi(rest, :entry, <<>>, <<>>, [])

  # SS3 — ESC O <byte>
  defp parse_escape(<<?O, final, rest::binary>>), do: {:ok, [{:ss3, final}], rest}
  defp parse_escape(<<?O>>), do: :incomplete

  # OSC — ESC ] <payload> ST
  defp parse_escape(<<?], rest::binary>>) do
    case scan_string(rest, <<>>) do
      {:done, payload, remaining} -> {:ok, [{:osc, payload}], remaining}
      :incomplete -> :incomplete
    end
  end

  # DCS / APC / PM / SOS — recognised string types, rejected outright.
  defp parse_escape(<<?P, rest::binary>>), do: reject_string(rest, <<@esc, ?P>>)
  defp parse_escape(<<?_, rest::binary>>), do: reject_string(rest, <<@esc, ?_>>)
  defp parse_escape(<<?^, rest::binary>>), do: reject_string(rest, <<@esc, ?^>>)
  defp parse_escape(<<?X, rest::binary>>), do: reject_string(rest, <<@esc, ?X>>)

  # ESC <other> — a standalone escape.
  defp parse_escape(<<byte, rest::binary>>), do: {:ok, [{:esc, byte}], rest}

  # --- CSI body ---
  #
  # A faithful encoding of the diagram's csi_entry / csi_param / csi_intermediate
  # / csi_ignore states. `params` and `inter` are the two collection buffers;
  # `tokens` carries (in reverse) any C0 controls executed mid-sequence, so they
  # surface in stream order alongside the eventual CSI token.
  #
  # `state` is one of :entry, :param, :intermediate, :ignore.

  defp parse_csi(<<>>, _state, _params, _inter, _tokens), do: :incomplete

  # --- "anywhere" transitions, honoured in every state ---

  # ESC abandons the in-flight sequence and begins a fresh escape.
  defp parse_csi(<<@esc, _::binary>> = remaining, _state, _params, _inter, tokens),
    do: {:ok, Enum.reverse(tokens), remaining}

  # CAN and SUB abort the sequence and return to ground.
  defp parse_csi(<<byte, rest::binary>>, _state, _params, _inter, tokens)
       when byte in [@can, @sub],
       do: {:ok, Enum.reverse(tokens), rest}

  # Other C0 controls execute in place; the sequence continues in its state.
  defp parse_csi(<<byte, rest::binary>>, state, params, inter, tokens) when byte < 0x20,
    do: parse_csi(rest, state, params, inter, [{:text, <<byte>>} | tokens])

  # DEL is ignored inside a sequence.
  defp parse_csi(<<0x7F, rest::binary>>, state, params, inter, tokens),
    do: parse_csi(rest, state, params, inter, tokens)

  # --- final byte (0x40..0x7E) ---

  # In csi_ignore the sequence is discarded: consume the final, emit nothing.
  defp parse_csi(<<final, rest::binary>>, :ignore, _params, _inter, tokens)
       when final in 0x40..0x7E,
       do: {:ok, Enum.reverse(tokens), rest}

  # Otherwise the final byte dispatches the collected sequence.
  defp parse_csi(<<final, rest::binary>>, _state, params, inter, tokens)
       when final in 0x40..0x7E,
       do: {:ok, Enum.reverse(tokens, [{:csi, params, inter, final}]), rest}

  # --- csi_ignore: swallow every other byte until the final ---

  defp parse_csi(<<_byte, rest::binary>>, :ignore, params, inter, tokens),
    do: parse_csi(rest, :ignore, params, inter, tokens)

  # --- intermediate bytes (0x20..0x2F): collect, move to csi_intermediate ---

  defp parse_csi(<<byte, rest::binary>>, state, params, inter, tokens)
       when state in [:entry, :param, :intermediate] and byte in 0x20..0x2F,
       do: parse_csi(rest, :intermediate, params, <<inter::binary, byte>>, tokens)

  # Once in csi_intermediate, any 0x30..0x3F byte is out of order → csi_ignore.
  defp parse_csi(<<byte, rest::binary>>, :intermediate, params, inter, tokens)
       when byte in 0x30..0x3F,
       do: parse_csi(rest, :ignore, params, inter, tokens)

  # --- parameter bytes: digits and ';' ---

  defp parse_csi(<<byte, rest::binary>>, state, params, inter, tokens)
       when state in [:entry, :param] and (byte in 0x30..0x39 or byte == ?;),
       do: parse_csi(rest, :param, <<params::binary, byte>>, inter, tokens)

  # Colon is reserved by the diagram → csi_ignore.
  defp parse_csi(<<?:, rest::binary>>, state, params, inter, tokens)
       when state in [:entry, :param],
       do: parse_csi(rest, :ignore, params, inter, tokens)

  # Private-marker bytes (0x3C..0x3F) are legal only as the first byte.
  defp parse_csi(<<byte, rest::binary>>, :entry, params, inter, tokens)
       when byte in 0x3C..0x3F,
       do: parse_csi(rest, :param, params, <<inter::binary, byte>>, tokens)

  defp parse_csi(<<byte, rest::binary>>, :param, params, inter, tokens)
       when byte in 0x3C..0x3F,
       do: parse_csi(rest, :ignore, params, inter, tokens)

  # Anything else (e.g. a >= 0x80 byte) cannot appear in a 7-bit CSI → csi_ignore.
  defp parse_csi(<<_byte, rest::binary>>, _state, params, inter, tokens),
    do: parse_csi(rest, :ignore, params, inter, tokens)

  # --- string-terminated sequences (OSC payload, rejected DCS/APC/PM/SOS) ---

  defp reject_string(rest, prefix) do
    case scan_string(rest, <<>>) do
      {:done, payload, remaining} ->
        {:ok, [{:invalid, <<prefix::binary, payload::binary>>}], remaining}

      :incomplete ->
        :incomplete
    end
  end

  # Consume bytes up to a String Terminator: BEL (0x07) or ESC \.
  defp scan_string(<<@bel, rest::binary>>, acc), do: {:done, acc, rest}
  defp scan_string(<<@esc, ?\\, rest::binary>>, acc), do: {:done, acc, rest}
  defp scan_string(<<@esc>>, _acc), do: :incomplete
  defp scan_string(<<>>, _acc), do: :incomplete
  defp scan_string(<<b, rest::binary>>, acc), do: scan_string(rest, <<acc::binary, b>>)
end
