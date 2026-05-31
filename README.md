# Vtex

A streaming VT/ANSI escape-sequence library for Elixir.

Vtex handles terminal I/O in both directions for SSH/Telnet game servers, BBS
engines and MUD frameworks: it parses raw input bytes into semantic events, and
it builds the control sequences you write back to draw the screen.

It is **transport-agnostic and does no IO of its own** — input functions take
bytes you've read; output functions return bytes for you to write (to an SSH
channel, socket, or `IO`). It covers the gaps `IO.ANSI` leaves, such as
truecolor, the alternate screen buffer, and mouse/paste/focus reporting.

## Features

- Parses a raw byte stream into typed tokens (`:text`, `:csi`, `:ss3`, `:osc`, …),
  with a CSI parser faithful to [Paul Williams' DEC ANSI state machine](https://vt100.net/emu/dec_ansi_parser)
- Maps tokens to semantic events — keys, function keys, `Alt`/`Meta` keys,
  modified keys, SGR mouse, SGR colour — decoding UTF-8 input to whole characters
- Builds output sequences too — `Vtex.Output.ANSI` is a drop-in superset of `IO.ANSI`
  (verified byte-for-byte) adding truecolor, plus cursor/screen control, the
  alternate buffer, window title and hyperlinks
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
                       INPUT                                 OUTPUT
raw bytes (SSH / Telnet / TCP)                  game / application logic
    ↓                                                        ↓
Vtex.Input.Stream    ← buffer + cap                    Vtex.Output.Cursor / Vtex.Output.Screen
    ↓                                            Vtex.SGR.encode/1
Vtex.Input.Tokenizer ← bytes -> tokens                 Vtex.Mouse/Paste/Focus.enable
    ↓                                                        ↓
Vtex.Input     ← tokens -> events                control sequences (iodata)
    ↓                                                        ↓
game / application logic                         you write them to the transport
```

Both directions are pure functions over bytes: nothing here touches the
network or terminal directly.

## Usage

The typical flow is to keep a `Vtex.Input.Stream` in your session process state, feed
it incoming bytes, and interpret the resulting tokens:

```elixir
stream = Vtex.Input.Stream.new()

# Bytes arrive from the transport (here: arrow-up, then "hi").
{tokens, stream} = Vtex.Input.Stream.feed(stream, <<0x1B, ?[, ?A, ?h, ?i>>)
#=> {[{:csi, "", "", ?A}, {:text, "hi"}], %Vtex.Input.Stream{}}

Vtex.Input.interpret(tokens)
#=> [:arrow_up, {:char, ?h}, {:char, ?i}]
```

Partial sequences are buffered automatically. If a sequence is split across two
chunks, the first feed emits nothing and the bytes are held until the next feed
completes them:

```elixir
{[], stream}              = Vtex.Input.Stream.feed(stream, <<0x1B, ?[>>)
{[{:csi, "", "", ?A}], _} = Vtex.Input.Stream.feed(stream, <<?A>>)
```

### The Escape key

A lone `Escape` keypress (`0x1B`) is byte-for-byte the start of every
`ESC`-prefixed sequence (arrow keys, `Alt`+key, …), so a stateless parser can't
tell them apart without timing. `Vtex.Input.Stream` holds a trailing lone `ESC` rather
than guess; you resolve it with `pending?/1` (arm a timer) and `flush/1` (commit
the pending `ESC`). The idiomatic OTP shape mirrors how Neovim does it — an
active socket delivering messages plus a one-shot `Process.send_after/3` timer:

```elixir
# socket opened with [active: :once]
def handle_info({:tcp, sock, data}, state) do
  {tokens, stream} = Vtex.Input.Stream.feed(state.stream, data)
  dispatch(Vtex.Input.interpret(tokens))
  :inet.setopts(sock, active: :once)
  {:noreply, state |> Map.put(:stream, stream) |> rearm_esc_timer()}
end

def handle_info(:esc_timeout, state) do
  # idle with bytes pending → that ESC was the Escape key
  {tokens, stream} = Vtex.Input.Stream.flush(state.stream)
  dispatch(Vtex.Input.interpret(tokens))
  {:noreply, %{state | stream: stream, esc_timer: nil}}
end

defp rearm_esc_timer(state) do
  if state.esc_timer, do: Process.cancel_timer(state.esc_timer)
  timer =
    if Vtex.Input.Stream.pending?(state.stream),
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
See `Vtex.Input.Stream` for the full rationale.

### Tokens

`Vtex.Input.Tokenizer` produces these tokens:

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

Holding `Shift`/`Ctrl`/`Alt` produces `{:key, base, mods}` — e.g. `Shift+Up` is
`{:key, :arrow_up, [:shift]}` and `Ctrl+F5` is `{:key, {:function, 5}, [:ctrl]}`
— where `base` is the unmodified event and `mods` is drawn from `:shift`,
`:alt`, `:ctrl`, `:meta`.

### Bracketed paste

Enable it with `Vtex.Paste.enable()` (disable with `Vtex.Paste.disable()`).
Pasted text then arrives bracketed by `:paste_start` and `:paste_end` events,
with the content as ordinary events in between; accumulate those (treating them
as literal text) until `:paste_end`, applying your own size limit. The parser
stays stateless and never buffers the paste itself.

### Reports and focus

A **Cursor Position Report** (`CSI r ; c R`, the reply to writing `CSI 6n`)
arrives as `{:cursor_position, row, col}` — the in-band way to read the cursor,
or to probe terminal size when SSH/Telnet can't tell you. **Focus reporting**
(`Vtex.Focus.enable()`) delivers `:focus_in` / `:focus_out` as the window gains
and loses focus.

### Mouse

Mouse reporting is opt-in. Write `Vtex.Mouse.enable()` to the terminal to turn
it on (and `Vtex.Mouse.disable()` on teardown); events then arrive as `{:mouse,
%{action:, button:, x:, y:, mods:}}` via `Vtex.Input`. Only the modern SGR
encoding is supported. Pass `motion: :all` for bare pointer-motion events,
`:none` for press/release only, or the default `:drag` — see `Vtex.Mouse`.

```elixir
transport_write(Vtex.Mouse.enable())
# a left click at column 10, row 5 arrives as:
#=> {:mouse, %{action: :press, button: :left, x: 10, y: 5, mods: []}}
```

A standalone `Escape` keypress is inherently ambiguous against an `ESC`-prefixed
sequence; see [The Escape key](#the-escape-key) above for how you resolve it.

## Output

Output functions return iodata for you to write to the terminal — the library
never does IO itself.

`Vtex.Output.ANSI` is a **drop-in superset of `IO.ANSI`**: every `IO.ANSI` function is
mirrored byte-for-byte (the test suite asserts parity), so you can swap the
module name and keep your calls — plus it adds 24-bit truecolor, which
`IO.ANSI` can't express.

```elixir
transport_write([
  Vtex.Output.Screen.enter_alternate(),
  Vtex.Output.ANSI.clear(),
  Vtex.Output.ANSI.cursor(1, 1),
  Vtex.Output.ANSI.format([:bright, Vtex.Output.ANSI.true_color(255, 128, 0), "Hello, world"])
])
```

| Module | What it builds |
| --- | --- |
| `Vtex.Output.ANSI` | drop-in `IO.ANSI` superset — colours, styles, cursor, `format/1`, **truecolor** |
| `Vtex.Output.Cursor` | richer cursor control — save/restore, hide/show (beyond `IO.ANSI`) |
| `Vtex.Output.Screen` | clear variants, alternate buffer, scroll region |
| `Vtex.Output.OSC` | window title, clickable hyperlinks |
| `Vtex.SGR` | `parse/1` and `encode/1` — structured colour/style attributes |
| `Vtex.Mouse` / `Vtex.Paste` / `Vtex.Focus` | `enable/0` / `disable/0` mode toggles |

## Security

- **Buffer cap** (`256` bytes) prevents memory exhaustion from partial sequences.
- **OSC / DCS / APC / PM / SOS** sequences have unbounded payloads; DCS, APC, PM
  and SOS are rejected outright, and any sequence that overflows the cap is
  flushed as `{:invalid, …}`.
- **CSI** is bounded by its final byte and **SS3** is always three bytes, so
  neither poses a length risk.
- No timers are needed — the cap alone is sufficient defence.

Transport-layer concerns (connection limits, rate limiting) are out of scope.

## Development

Run the test suite with `mix test`. For a hands-on check against a real
terminal, run the interactive smoke test and press keys to watch how Vtex
interprets them (arrows, function keys, modified keys, `Alt`+key, mouse, UTF-8,
the Escape timeout):

```
dev/smoke
```

It's a development-only task (under `dev/`, never shipped in the package). The
`dev/smoke` wrapper runs it with `-noinput` so the Erlang shell doesn't compete
with the smoke reader for stdin; running `mix vtex.smoke` directly is refused
for that reason.

Static analysis runs via `mix lint`, which runs Credo (`--strict`) and Dialyzer
together. The fuzz tests (`test/input/tokenizer_property_test.exs`) throw random
byte soup at the parser to assert it never crashes, only emits well-formed
tokens, loses no bytes, and keeps the stream buffer bounded. CI
(`.github/workflows/ci.yml`) runs the test suite and `mix lint` on every push.

MIT
