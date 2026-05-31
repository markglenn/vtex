# Integrating Vtex

Vtex is transport-agnostic: it never touches a socket. You own the connection
and drive both directions through pure functions —

- **input:** feed the bytes you read into `Vtex.Input.Stream`, then
  `Vtex.Input.interpret/1` turns the tokens into events;
- **output:** call `Vtex.Output.ANSI` / `Vtex.Output.Cursor` / `Vtex.Output.Screen`
  (and the `enable/0` toggles) to build control sequences, and write them
  yourself.

This guide wires it into a minimal interactive TCP server. SSH works the same
way — see the note at the end.

## A connection process

Run one process per connection. After accepting a socket, hand it to a
`GenServer` that owns the `Vtex.Input.Stream` and the screen state. The shape
below is the recommended pattern: an **active socket** delivers input as
messages, and a **`Process.send_after/3` timer** resolves the standalone
`Escape` key (see `Vtex.Input.Stream` for why).

```elixir
defmodule Demo.Session do
  use GenServer

  alias Vtex.Input
  alias Vtex.Output.{ANSI, Cursor, Screen}

  @esc_timeout 50

  def start_link(socket), do: GenServer.start_link(__MODULE__, socket)

  @impl true
  def init(socket) do
    # Turn on the input features we want, switch to the alternate screen,
    # set a title, and draw once.
    write(socket, [
      Vtex.Mouse.enable(),
      Vtex.Paste.enable(),
      Vtex.Focus.enable(),
      Vtex.Output.OSC.title("Vtex Demo"),
      Screen.enter_alternate(),
      Cursor.hide()
    ])

    state = %{socket: socket, stream: Input.Stream.new(), line: "", esc_timer: nil}
    render(state)
    :inet.setopts(socket, active: :once)
    {:ok, state}
  end

  @impl true
  def handle_info({:tcp, socket, data}, state) do
    {tokens, stream} = Input.Stream.feed(state.stream, data)
    state = %{state | stream: stream}

    case Enum.reduce(Input.interpret(tokens), {:cont, state}, &handle_event/2) do
      {:halt, state} ->
        {:stop, :normal, state}

      {:cont, state} ->
        render(state)
        :inet.setopts(socket, active: :once)
        {:noreply, rearm_esc_timer(state)}
    end
  end

  # Input went idle with a lone ESC pending — that was the Escape key.
  def handle_info(:esc_timeout, state) do
    {tokens, stream} = Input.Stream.flush(state.stream)
    state = %{state | stream: stream, esc_timer: nil}

    case Enum.reduce(Input.interpret(tokens), {:cont, state}, &handle_event/2) do
      {:halt, state} -> {:stop, :normal, state}
      {:cont, state} -> render(state); {:noreply, state}
    end
  end

  def handle_info({:tcp_closed, _socket}, state), do: {:stop, :normal, state}

  @impl true
  def terminate(_reason, state) do
    write(state.socket, [
      Cursor.show(),
      Screen.leave_alternate(),
      Vtex.Focus.disable(),
      Vtex.Paste.disable(),
      Vtex.Mouse.disable()
    ])
  end

  # --- events -> state ---

  # Ctrl-C (the character event for byte 3) quits.
  defp handle_event({:char, 3}, {_, state}), do: {:halt, state}
  defp handle_event(:escape, {_, state}), do: {:halt, state}

  defp handle_event(:enter, {_, state}), do: {:cont, %{state | line: ""}}
  defp handle_event(:backspace, {_, state}),
    do: {:cont, %{state | line: String.slice(state.line, 0..-2//1)}}

  defp handle_event({:char, cp}, {_, state}),
    do: {:cont, %{state | line: state.line <> <<cp::utf8>>}}

  defp handle_event({:mouse, %{action: :press, x: x, y: y}}, {_, state}),
    do: {:cont, Map.put(state, :status, "click @ #{x},#{y}")}

  # Ignore anything we don't handle (arrows, focus, paste markers, …).
  defp handle_event(_event, acc), do: acc

  # --- rendering ---

  defp render(state) do
    write(state.socket, [
      Screen.clear(),
      Cursor.to(1, 1),
      ANSI.format([:bright, "Vtex demo — type, Ctrl-C to quit"]),
      Cursor.to(3, 1),
      "> ",
      state.line,
      status(state)
    ])
  end

  defp status(%{status: s}), do: [Cursor.to(5, 1), ANSI.format([:faint, s])]
  defp status(_), do: []

  # --- transport ---

  defp write(socket, iodata), do: :gen_tcp.send(socket, iodata)

  defp rearm_esc_timer(state) do
    if state.esc_timer, do: Process.cancel_timer(state.esc_timer)

    timer =
      if Input.Stream.pending?(state.stream),
        do: Process.send_after(self(), :esc_timeout, @esc_timeout)

    %{state | esc_timer: timer}
  end
end
```

An acceptor just spins these up:

```elixir
{:ok, listen} = :gen_tcp.listen(4000, [:binary, packet: :raw, active: false, reuseaddr: true])

accept = fn accept ->
  {:ok, socket} = :gen_tcp.accept(listen)
  {:ok, pid} = Demo.Session.start_link(socket)
  :ok = :gen_tcp.controlling_process(socket, pid)
  accept.(accept)
end

accept.(accept)
```

> Most terminals send line-based input until you put them in raw/character mode.
> For a quick local try, `stty -icanon -echo` in another shell before
> `nc localhost 4000`, or drive it over a transport that already negotiates raw
> mode (SSH, or Telnet with the right options).

## Notes

- **Why the timer:** arrow/function keys arrive as a burst and resolve
  instantly; only a real `Escape` press waits out `@esc_timeout`. The
  `pending?/1` check means the timer is armed only when a lone `ESC` is
  outstanding. Both message handlers run in the same process, so there's no race
  — see `Vtex.Input.Stream` for the full rationale and tuning.
- **Bounded input:** `Vtex.Input.Stream` caps its buffer at
  `Vtex.Input.Stream.max_buffer/0` bytes, so malformed or hostile input can't
  grow it without bound.
- **Pasting:** with `Vtex.Paste` enabled you get `:paste_start` / `:paste_end`
  around the pasted events; accumulate between them (with your own limit) to
  treat the block as literal text.

## Over SSH

The structure is identical — accept input as messages and write sequences back.
With Erlang's `:ssh` daemon you implement a channel and handle `{:ssh_cm, cm,
{:data, ch, _, data}}` exactly like `{:tcp, socket, data}` above. SSH also gives
you the terminal **size** out of band — the `pty-req` and `window-change`
messages carry width/height — so you don't need the in-band cursor-report trick.
