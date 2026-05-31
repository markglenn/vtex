defmodule Vtex.Input.Stream do
  @moduledoc """
  Stateful streaming wrapper around `Vtex.Input.Tokenizer`.

  Owns the leftover buffer between chunks and enforces a hard buffer cap. It is
  designed to live as a plain struct inside a session process' state — it is not
  a `GenServer` and starts no processes of its own.

  ## Usage

      stream = Vtex.Input.Stream.new()
      {tokens, stream} = Vtex.Input.Stream.feed(stream, first_chunk)
      {more_tokens, stream} = Vtex.Input.Stream.feed(stream, second_chunk)

  Sequences split across chunk boundaries are reassembled automatically: the
  tokenizer's leftover is held in the struct and prepended to the next chunk.

  ## Buffer cap

  The buffer is capped at `#{256}` bytes. CSI sequences are bounded by their
  final byte and SS3 sequences are always three bytes, so the only way to grow
  the buffer without bound is a never-terminated OSC (or a rejected DCS/APC/PM/
  SOS) string. When the leftover exceeds the cap after tokenization, it is
  emitted as a single `{:invalid, buffer}` token and the buffer is cleared.

  `byte_size/1` is O(1), so the cap check is effectively free. The buffer is
  always small, so the O(n) binary concat used to prepend it is negligible. No
  timers are needed — the cap alone defends against memory-exhaustion input.

  ## Resolving the Escape key

  A standalone `Escape` keypress (`0x1B`) is byte-for-byte ambiguous with the
  start of an `ESC`-prefixed sequence (arrow keys, `Alt`+key, …). A stateless
  parser cannot tell them apart, so `feed/2` *holds* a trailing lone `ESC` in
  the buffer rather than guessing. The caller resolves it with a timeout, using
  `pending?/1` to arm a timer and `flush/1` to commit the pending `ESC`.

  The idiomatic OTP shape mirrors how Neovim does it — an async reader (an
  active socket delivering messages) plus a one-shot timer
  (`Process.send_after/3`), rather than a blocking read-with-timeout:

      # socket opened with [active: :once]
      def handle_info({:tcp, sock, data}, state) do
        {tokens, stream} = Vtex.Input.Stream.feed(state.stream, data)
        dispatch(Vtex.Input.interpret(tokens))
        :inet.setopts(sock, active: :once)
        {:noreply, state |> Map.put(:stream, stream) |> rearm_esc_timer()}
      end

      def handle_info(:esc_timeout, state) do
        # Idle with bytes pending: that ESC was the Escape key.
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

  Both clauses run in the same process, so they are serialised — there is no
  data race and no lock is needed. A timer that fires just as new input arrives
  can leave a stale `:esc_timeout` in the mailbox, but that is harmless:
  `flush/1` on an empty buffer is a no-op, and message ordering guarantees the
  stale timeout is handled before any later-arriving `ESC` is fed, so it can
  never flush the wrong one.

  Arming the timer only while `pending?/1` is what keeps this cheap: a
  multi-byte sequence (arrow key, function key, `Alt`+key) arrives as one burst,
  so `feed/2` consumes it whole and the stream never goes pending — those keys
  incur **no** latency. The clock runs in exactly one place: right after a lone
  `ESC` with nothing behind it, i.e. an actual `Escape` keypress.

  The timeout is the single tuning knob, and it's a ceiling rather than a fixed
  delay — a continuation byte arriving cancels and re-evaluates it. It must be
  long enough that a sequence split across packets isn't chopped, short enough
  that `Escape` feels responsive. `50` ms (used above) matches Neovim's default
  `ttimeoutlen`; modern Vim uses `100`. On a local/LAN link `10`–`30` ms feels
  snappier and is still safe; raise it for genuinely laggy connections. This is
  the same tradeoff `vim`'s `ttimeoutlen` and `readline`'s `keyseq-timeout` make.

  A simpler blocking `recv(socket, 0, timeout)` loop works too — `:infinity`
  normally, the short timeout only while `pending?/1`, calling `flush/1` on
  `{:error, :timeout}` — but it blocks the process while waiting out the window.
  """

  alias Vtex.Input.Tokenizer

  @max_buffer 256

  defstruct buffer: <<>>

  @type t :: %__MODULE__{buffer: binary()}

  @doc """
  Create a new, empty stream.

  ## Examples

      iex> Vtex.Input.Stream.new()
      %Vtex.Input.Stream{buffer: ""}
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Feed a chunk of incoming bytes, returning emitted tokens and the updated stream.

  The current buffer is prepended to `incoming` before tokenizing. Any leftover
  becomes the new buffer, unless it exceeds the cap, in which case it is emitted
  as `{:invalid, buffer}` and the buffer is cleared.

  ## Examples

      iex> {tokens, _stream} = Vtex.Input.Stream.feed(Vtex.Input.Stream.new(), "hi")
      iex> tokens
      [{:text, "hi"}]
  """
  @spec feed(t(), binary()) :: {[Tokenizer.token()], t()}
  def feed(%__MODULE__{buffer: buffer} = state, incoming) when is_binary(incoming) do
    {tokens, leftover} = Tokenizer.tokenize(<<buffer::binary, incoming::binary>>)

    if byte_size(leftover) > @max_buffer do
      {tokens ++ [{:invalid, leftover}], %{state | buffer: <<>>}}
    else
      {tokens, %{state | buffer: leftover}}
    end
  end

  @doc """
  Whether the stream is holding an unresolved partial sequence.

  The buffer is non-empty only when input ended mid-sequence — most often a lone
  trailing `ESC`. Use this to arm a read timeout only when it matters (read with
  `:infinity` otherwise) and call `flush/1` if that read times out. See
  "Resolving the Escape key" in the module docs.

  ## Examples

      iex> Vtex.Input.Stream.pending?(Vtex.Input.Stream.new())
      false

      iex> {[], stream} = Vtex.Input.Stream.feed(Vtex.Input.Stream.new(), <<0x1B>>)
      iex> Vtex.Input.Stream.pending?(stream)
      true
  """
  @spec pending?(t()) :: boolean()
  def pending?(%__MODULE__{buffer: buffer}), do: buffer != <<>>

  @doc """
  Resolve any buffered bytes left over from an incomplete sequence.

  Call this when input has gone idle (e.g. your socket read timed out) and a
  pending `ESC` must finally be interpreted. The buffer — always either empty or
  the start of an unfinished escape sequence — is emitted as a single `{:text,
  ...}` token and cleared; `Vtex.Input` then turns the leading `ESC` into
  `:escape` and any trailing bytes into their literal events.

  This is the only place a `{:text, ...}` token can begin with `ESC`: it marks
  bytes the transport layer has decided are not the prefix of a longer sequence.

  ## Examples

      iex> {[], stream} = Vtex.Input.Stream.feed(Vtex.Input.Stream.new(), <<0x1B>>)
      iex> {tokens, stream} = Vtex.Input.Stream.flush(stream)
      iex> {tokens, Vtex.Input.Stream.pending?(stream)}
      {[{:text, <<0x1B>>}], false}

      iex> {[], stream} = Vtex.Input.Stream.feed(Vtex.Input.Stream.new(), <<0x1B>>)
      iex> {tokens, _stream} = Vtex.Input.Stream.flush(stream)
      iex> Vtex.Input.interpret(tokens)
      [:escape]
  """
  @spec flush(t()) :: {[Tokenizer.token()], t()}
  def flush(%__MODULE__{buffer: <<>>} = state), do: {[], state}
  def flush(%__MODULE__{buffer: buffer} = state), do: {[{:text, buffer}], %{state | buffer: <<>>}}

  @doc """
  The hard buffer cap, in bytes.

  ## Examples

      iex> Vtex.Input.Stream.max_buffer()
      256
  """
  @spec max_buffer() :: pos_integer()
  def max_buffer, do: @max_buffer
end
