# Vtex

A streaming VT/ANSI escape-sequence parser for Elixir.

Vtex is a tokenizer for VT/ANSI terminal escape sequences, designed for
SSH/Telnet game servers, BBS engines and MUD frameworks. It is the
input-parsing equivalent of the Rust [`vte`](https://crates.io/crates/vte)
crate.

**Scope: input parsing only.** Output encoding is a separate concern — use
[`IO.ANSI`](https://hexdocs.pm/elixir/IO.ANSI.html) from the standard library
for that.

## Features

- Parses a raw byte stream into typed tokens (`:text`, `:csi`, `:ss3`, `:osc`, …),
  with a CSI parser faithful to [Paul Williams' DEC ANSI state machine](https://vt100.net/emu/dec_ansi_parser)
- Maps tokens to semantic events — keys, function keys, `Alt`/`Meta` keys, SGR —
  decoding UTF-8 input to whole characters
- Handles streaming input correctly — partial sequences are buffered across chunks
- Resolves the standalone-`Escape`-vs-escape-sequence ambiguity with a
  caller-driven read timeout (no timers baked into the library)
- Defends against malformed or malicious input (hard buffer cap, rejection of
  unbounded sequences)
- Completely transport-agnostic — knows nothing about SSH, Telnet or TCP
- No external dependencies

## Installation

Add `vtex` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:vtex, "~> 0.1.0"}
  ]
end
```

## Architecture

```
raw bytes (from SSH / Telnet / TCP transport)
    ↓
Vtex.Stream      ← stateful wrapper, owns the leftover buffer + cap
    ↓
Vtex.Tokenizer   ← pure, stateless binary pattern matching
    ↓
[token stream]   ← {:text, ...}, {:csi, ...}, {:ss3, ...}, {:osc, ...}, ...
    ↓
Vtex.Input       ← maps tokens to semantic events
    ↓
[:enter, :arrow_up, {:char, ?h}, {:sgr, [{:fg, :red}]}]
    ↓
game / application logic
```

## Usage

The typical flow is to keep a `Vtex.Stream` in your session process state, feed
it incoming bytes, and interpret the resulting tokens:

```elixir
stream = Vtex.Stream.new()

# Bytes arrive from the transport (here: arrow-up, then "hi").
{tokens, stream} = Vtex.Stream.feed(stream, <<0x1B, ?[, ?A, ?h, ?i>>)
#=> {[{:csi, "", "", ?A}, {:text, "hi"}], %Vtex.Stream{}}

Vtex.Input.interpret(tokens)
#=> [:arrow_up, {:char, ?h}, {:char, ?i}]
```

Partial sequences are buffered automatically. If a sequence is split across two
chunks, the first feed emits nothing and the bytes are held until the next feed
completes them:

```elixir
{[], stream}              = Vtex.Stream.feed(stream, <<0x1B, ?[>>)
{[{:csi, "", "", ?A}], _} = Vtex.Stream.feed(stream, <<?A>>)
```

### The Escape key

A lone `Escape` keypress (`0x1B`) is byte-for-byte the start of every
`ESC`-prefixed sequence (arrow keys, `Alt`+key, …), so a stateless parser can't
tell them apart without timing. `Vtex.Stream` holds a trailing lone `ESC` rather
than guess; you resolve it with `pending?/1` (arm a timer) and `flush/1` (commit
the pending `ESC`). The idiomatic OTP shape mirrors how Neovim does it — an
active socket delivering messages plus a one-shot `Process.send_after/3` timer:

```elixir
# socket opened with [active: :once]
def handle_info({:tcp, sock, data}, state) do
  {tokens, stream} = Vtex.Stream.feed(state.stream, data)
  dispatch(Vtex.Input.interpret(tokens))
  :inet.setopts(sock, active: :once)
  {:noreply, state |> Map.put(:stream, stream) |> rearm_esc_timer()}
end

def handle_info(:esc_timeout, state) do
  # idle with bytes pending → that ESC was the Escape key
  {tokens, stream} = Vtex.Stream.flush(state.stream)
  dispatch(Vtex.Input.interpret(tokens))
  {:noreply, %{state | stream: stream, esc_timer: nil}}
end

defp rearm_esc_timer(state) do
  if state.esc_timer, do: Process.cancel_timer(state.esc_timer)
  timer =
    if Vtex.Stream.pending?(state.stream),
      do: Process.send_after(self(), :esc_timeout, 50)
  %{state | esc_timer: timer}
end
```

Both clauses run in the same process, so they're serialised — no data race, no
lock. Arrow and function keys arrive as a single burst, resolve immediately, and
never run the timer; only a real `Escape` press does, and even then a
continuation byte cancels it early. `50` ms matches Neovim's default
`ttimeoutlen` (modern Vim uses `100`); drop to `10`–`30` ms on fast links for a
snappier Escape. A simpler blocking `recv(socket, 0, timeout)` loop works too.
See `Vtex.Stream` for the full rationale.

### Tokens

`Vtex.Tokenizer` produces these tokens:

| Token | Meaning |
| --- | --- |
| `{:text, binary}` | A run of printable / control bytes |
| `{:csi, params, intermediates, final}` | A Control Sequence Introducer — `ESC [ … X` |
| `{:ss3, byte}` | A single-shift-3 key — `ESC O X` |
| `{:osc, payload}` | An Operating System Command — `ESC ] … ST` |
| `{:esc, byte}` | A standalone escape — `ESC <other>` |
| `{:invalid, binary}` | A failed or rejected sequence |

Truncated sequences are never emitted as tokens; they are returned as the
leftover binary so the caller can buffer them until more bytes arrive.

### Events

`Vtex.Input` maps tokens to semantic events: `:enter`, `:backspace`, `:escape`,
`:tab`, the arrow keys, editing/navigation keys (`:home`, `:end`, `:insert`,
`:delete`, `:page_up`, `:page_down`), `{:function, 1..12}`, `{:alt, byte}` for
`Alt`/`Meta`-modified keys, `{:char, codepoint}` (UTF-8 decoded), `{:sgr,
attributes}` and `{:unknown, token}` for anything unrecognised. Arrow and
editing keys are recognised in both their CSI and SS3 forms.

A standalone `Escape` keypress is inherently ambiguous against an `ESC`-prefixed
sequence; see [The Escape key](#the-escape-key) above for how you resolve it.

## Security

- **Buffer cap** (`256` bytes) prevents memory exhaustion from partial sequences.
- **OSC / DCS / APC / PM / SOS** sequences have unbounded payloads; DCS, APC, PM
  and SOS are rejected outright, and any sequence that overflows the cap is
  flushed as `{:invalid, …}`.
- **CSI** is bounded by its final byte and **SS3** is always three bytes, so
  neither poses a length risk.
- No timers are needed — the cap alone is sufficient defence.

Transport-layer concerns (connection limits, rate limiting) are out of scope.

## License

MIT
