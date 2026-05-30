defmodule Vtex.Stream do
  @moduledoc """
  Stateful streaming wrapper around `Vtex.Tokenizer`.

  Owns the leftover buffer between chunks and enforces a hard buffer cap. It is
  designed to live as a plain struct inside a session process' state — it is not
  a `GenServer` and starts no processes of its own.

  ## Usage

      stream = Vtex.Stream.new()
      {tokens, stream} = Vtex.Stream.feed(stream, first_chunk)
      {more_tokens, stream} = Vtex.Stream.feed(stream, second_chunk)

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
  """

  alias Vtex.Tokenizer

  @max_buffer 256

  defstruct buffer: <<>>

  @type t :: %__MODULE__{buffer: binary()}

  @doc """
  Create a new, empty stream.

  ## Examples

      iex> Vtex.Stream.new()
      %Vtex.Stream{buffer: ""}
  """
  @spec new() :: t()
  def new(), do: %__MODULE__{}

  @doc """
  Feed a chunk of incoming bytes, returning emitted tokens and the updated stream.

  The current buffer is prepended to `incoming` before tokenizing. Any leftover
  becomes the new buffer, unless it exceeds the cap, in which case it is emitted
  as `{:invalid, buffer}` and the buffer is cleared.

  ## Examples

      iex> {tokens, _stream} = Vtex.Stream.feed(Vtex.Stream.new(), "hi")
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
  The hard buffer cap, in bytes.

  ## Examples

      iex> Vtex.Stream.max_buffer()
      256
  """
  @spec max_buffer() :: pos_integer()
  def max_buffer(), do: @max_buffer
end
