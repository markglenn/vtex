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

- Parses a raw byte stream into typed tokens (`:text`, `:csi`, `:ss3`, `:osc`, …)
- Handles streaming input correctly — partial sequences are buffered across chunks
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
#=> {[{:csi, "", ?A}, {:text, "hi"}], %Vtex.Stream{}}

Vtex.Input.interpret(tokens)
#=> [:arrow_up, {:char, ?h}, {:char, ?i}]
```

Partial sequences are buffered automatically. If a sequence is split across two
chunks, the first feed emits nothing and the bytes are held until the next feed
completes them:

```elixir
{[], stream}          = Vtex.Stream.feed(stream, <<0x1B, ?[>>)
{[{:csi, "", ?A}], _} = Vtex.Stream.feed(stream, <<?A>>)
```

### Tokens

`Vtex.Tokenizer` produces these tokens:

| Token | Meaning |
| --- | --- |
| `{:text, binary}` | A run of printable / control bytes |
| `{:csi, params, final}` | A Control Sequence Introducer — `ESC [ … X` |
| `{:ss3, byte}` | A single-shift-3 key — `ESC O X` |
| `{:osc, payload}` | An Operating System Command — `ESC ] … ST` |
| `{:esc, byte}` | A standalone escape — `ESC <other>` |
| `{:invalid, binary}` | A failed or rejected sequence |

Truncated sequences are never emitted as tokens; they are returned as the
leftover binary so the caller can buffer them until more bytes arrive.

### Events

`Vtex.Input` maps tokens to semantic events: `:enter`, `:backspace`, `:escape`,
`:tab`, the arrow keys, editing/navigation keys (`:home`, `:end`, `:insert`,
`:delete`, `:page_up`, `:page_down`), `{:function, 1..12}`, `{:char, byte}`,
`{:sgr, attributes}` and `{:unknown, token}` for anything unrecognised. Arrow
and editing keys are recognised in both their CSI and SS3 forms.

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
