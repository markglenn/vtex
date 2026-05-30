defmodule Vtex.Tokenizer do
  @moduledoc """
  Pure, stateless tokenizer for VT/ANSI escape sequences.

  Takes a binary and returns a list of typed tokens plus a leftover binary
  containing any trailing bytes that form an incomplete sequence. The leftover
  is meant to be prepended to the next chunk of input (see `Vtex.Stream`).

  The tokenizer is modeled on
  [Paul Williams' ANSI parser state machine](https://vt100.net/emu/dec_ansi_parser),
  borrowing its byte classes and, inside a control sequence, its "anywhere"
  transitions: an `ESC` restarts parsing, `CAN`/`SUB` abort the sequence, other
  C0 controls are passed through (executed in place) while the sequence
  continues, and `DEL` is ignored. It has no state and no side effects, so it is
  fully testable with raw strings.

  It is *not* a complete implementation of the reference parser — see
  "Deviations from the reference parser" below.

  ## Token types

      {:text, binary()}                            # run of printable / control bytes
      {:csi, params :: binary(), final :: byte()}  # ESC [ ... X
      {:ss3, byte()}                               # ESC O X
      {:osc, payload :: binary()}                  # ESC ] ... ST
      {:esc, byte()}                               # ESC <other>
      {:invalid, binary()}                         # failed / rejected sequence

  Truncated sequences are never emitted as tokens; they are returned as the
  leftover binary so the caller can buffer them until more bytes arrive.

  ## Byte ranges

    * CSI parameter / intermediate bytes: `0x20..0x3F`
    * CSI final byte: `0x40..0x7E`
    * SS3: `ESC O <byte>` — always exactly three bytes
    * OSC: `ESC ] <payload> ST` where ST is `ESC \\` or `BEL` (`0x07`)

  `DCS`, `APC`, `PM` and `SOS` strings are recognised and immediately rejected
  as `{:invalid, ...}` — no game/BBS context needs them, and their unbounded
  payloads are a denial-of-service vector.

  ## Deviations from the reference parser

  This is a tokenizer, not a terminal, so several parts of the diagram are
  intentionally absent or simplified:

    * **Only the CSI body honours the "anywhere" transitions.** `ESC`, `CAN`,
      `SUB` and C0 controls get no special treatment inside OSC/string scanning
      or in the `escape` state itself — e.g. `ESC ESC` is emitted as a lone
      `{:esc, 0x1B}` rather than re-entering the escape state, and a stray
      control inside an OSC payload is copied verbatim.
    * **No parameter/intermediate split and no `csi_ignore` state.** Every byte
      in `0x20..0x3F` is accumulated into one `params` binary; malformed
      orderings (a `:` colon, or a parameter byte after an intermediate) are
      preserved rather than ignored.
    * **No 8-bit C1 controls.** Only the 7-bit `ESC`-prefixed forms are
      recognised; bytes `0x80..0x9F` are treated as ordinary text, which is
      what UTF-8 continuation bytes require anyway.
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
          | {:csi, binary(), byte()}
          | {:ss3, byte()}
          | {:osc, binary()}
          | {:esc, byte()}
          | {:invalid, binary()}

  @doc """
  Tokenize a binary into a list of tokens and a leftover binary.

  The leftover is the unconsumed tail when input ends mid-sequence. Pass it back
  prepended to the next chunk to resume parsing.

  ## Examples

      iex> Vtex.Tokenizer.tokenize("hi")
      {[{:text, "hi"}], ""}

      iex> Vtex.Tokenizer.tokenize(<<0x1B, ?[, ?A>>)
      {[{:csi, "", ?A}], ""}

      iex> Vtex.Tokenizer.tokenize(<<?a, 0x1B, ?[>>)
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
  defp parse_escape(<<?[, rest::binary>>), do: parse_csi(rest, <<>>, [])

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
  # `tokens` accumulates (in reverse) any C0 controls executed mid-sequence, so
  # they surface in stream order alongside the eventual CSI token. This mirrors
  # the "anywhere" transitions of the reference state machine.

  defp parse_csi(<<>>, _params, _tokens), do: :incomplete

  # ESC abandons the in-flight sequence and begins a fresh escape.
  defp parse_csi(<<@esc, _::binary>> = remaining, _params, tokens),
    do: {:ok, Enum.reverse(tokens), remaining}

  # CAN and SUB abort the sequence and return to ground.
  defp parse_csi(<<byte, rest::binary>>, _params, tokens) when byte in [@can, @sub],
    do: {:ok, Enum.reverse(tokens), rest}

  # Parameter and intermediate bytes accumulate into the params binary.
  defp parse_csi(<<byte, rest::binary>>, params, tokens) when byte in 0x20..0x3F,
    do: parse_csi(rest, <<params::binary, byte>>, tokens)

  # A final byte completes and dispatches the sequence.
  defp parse_csi(<<final, rest::binary>>, params, tokens) when final in 0x40..0x7E,
    do: {:ok, Enum.reverse(tokens, [{:csi, params, final}]), rest}

  # DEL is ignored inside a sequence.
  defp parse_csi(<<0x7F, rest::binary>>, params, tokens),
    do: parse_csi(rest, params, tokens)

  # Any other C0 control executes in place; the sequence continues.
  defp parse_csi(<<byte, rest::binary>>, params, tokens) when byte < 0x20,
    do: parse_csi(rest, params, [{:text, <<byte>>} | tokens])

  # A high byte (>= 0x80) cannot appear in a 7-bit CSI; reject as malformed.
  defp parse_csi(<<byte, rest::binary>>, params, tokens),
    do: {:ok, Enum.reverse(tokens, [{:invalid, <<@esc, ?[, params::binary, byte>>}]), rest}

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
