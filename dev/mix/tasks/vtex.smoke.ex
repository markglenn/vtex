defmodule Mix.Tasks.Vtex.Smoke do
  @shortdoc "Interactive real-terminal smoke test for Vtex input"

  @moduledoc """
  Reads your keystrokes in raw mode and runs them through the real
  `Vtex.Stream` -> `Vtex.Input` pipeline, printing the events Vtex produces.

  It uses the same `pending?`/`flush` + timer pattern documented in
  `Vtex.Stream`, so the Escape key resolves via the timeout exactly as it would
  in a server.

      mix vtex.smoke

  Press keys; watch the events. Ctrl-C to quit. If keystrokes seem swallowed or
  doubled, the Erlang shell is competing for stdin — run with it disabled:

      ELIXIR_ERL_OPTIONS="-noinput" mix vtex.smoke

  All terminal I/O goes straight to the controlling tty device (discovered via
  `ps`): input is streamed by `cat -u <device>` as a port, output is written to
  the device directly. This sidesteps Erlang's standard IO, so it works under
  `-noinput` and restores the terminal on exit. If a hard kill ever leaves it
  raw, run `reset`.

  This task is development-only: it lives under `dev/`, is compiled only in the
  `:dev` environment, and is never included in the published package.
  """

  use Mix.Task

  @requirements ["compile"]

  # Ctrl-C arrives as byte 0x03 because we disable signal generation (-isig).
  @quit 3
  @esc_timeout_ms 50

  @impl Mix.Task
  def run(_args) do
    dev = tty_device!()
    saved = capture_tty!(dev)
    {:ok, out} = :file.open(String.to_charlist(dev), [:write, :binary, :raw])

    try do
      set_raw!(dev)
      :file.write(out, Vtex.Mouse.enable())
      port = open_reader!(dev)
      intro(out)
      loop(out, port, Vtex.Stream.new())
    after
      :file.write(out, Vtex.Mouse.disable())
      System.cmd("sh", ["-c", "stty #{saved} < #{dev}"])
      :file.close(out)
    end
  end

  # --- find the controlling terminal device (Erlang's subprocesses have no
  #     controlling terminal, so /dev/tty fails; resolve the real path instead) ---

  defp tty_device! do
    resolve_tty(System.pid()) || resolve_tty(ppid(System.pid())) ||
      Mix.raise("""
      vtex.smoke: couldn't determine the controlling terminal.
      Run it directly in an interactive terminal (not piped, not in CI).
      """)
  end

  defp resolve_tty(nil), do: nil

  defp resolve_tty(pid) do
    with {out, 0} <- System.cmd("ps", ["-o", "tty=", "-p", pid]),
         name when name not in ["", "?", "??"] <- String.trim(out),
         dev = if(String.starts_with?(name, "/"), do: name, else: "/dev/" <> name),
         true <- File.exists?(dev) do
      dev
    else
      _ -> nil
    end
  end

  defp ppid(pid) do
    case System.cmd("ps", ["-o", "ppid=", "-p", pid]) do
      {out, 0} -> out |> String.trim() |> nil_if_blank()
      _ -> nil
    end
  end

  defp nil_if_blank(""), do: nil
  defp nil_if_blank(s), do: s

  # --- terminal mode (operate on the resolved device by name) ---

  defp capture_tty!(dev) do
    case System.cmd("sh", ["-c", "stty -g < #{dev}"]) do
      {saved, 0} -> String.trim(saved)
      {_, _} -> Mix.raise("vtex.smoke: could not read terminal settings from #{dev}.")
    end
  end

  defp set_raw!(dev) do
    # -icanon: byte at a time; -echo: no echo; -isig: Ctrl-C/Z become bytes;
    # -opost: no output post-processing (we emit explicit \r\n ourselves).
    case System.cmd("sh", ["-c", "stty -icanon -echo -isig -opost min 1 time 0 < #{dev}"]) do
      {_, 0} -> :ok
      {_, _} -> Mix.raise("vtex.smoke: could not set raw mode on #{dev}.")
    end
  end

  # --- reader: `cat -u <device>` streams the tty to us as a port. cat opens the
  #     device by name, so it needs no controlling terminal and never blocks on
  #     :raw-file quirks. -u keeps it unbuffered so keystrokes arrive promptly. ---

  defp open_reader!(dev) do
    cat = System.find_executable("cat") || Mix.raise("vtex.smoke: `cat` not found in PATH.")
    Port.open({:spawn_executable, cat}, [:binary, :stream, :exit_status, {:args, ["-u", dev]}])
  end

  # --- main loop: feed -> interpret -> print, with the Escape-resolving timeout ---

  defp loop(out, port, stream) do
    timeout = if Vtex.Stream.pending?(stream), do: @esc_timeout_ms, else: :infinity

    receive do
      {^port, {:data, data}} ->
        if quit?(data) do
          Port.close(port)
          pute(out, "[quit]")
        else
          {tokens, stream} = Vtex.Stream.feed(stream, data)
          show(out, data, Vtex.Input.interpret(tokens))
          loop(out, port, stream)
        end

      {^port, {:exit_status, status}} ->
        pute(out, "[reader exited: #{status}]")
    after
      timeout ->
        # Idle with bytes pending -> that ESC was the Escape key.
        {tokens, stream} = Vtex.Stream.flush(stream)
        show(out, :timeout, Vtex.Input.interpret(tokens))
        loop(out, port, stream)
    end
  end

  defp quit?(data), do: :binary.match(data, <<@quit>>) != :nomatch

  # --- display (written straight to the tty device, with explicit \r\n) ---

  defp show(_out, :timeout, []), do: :ok

  defp show(out, src, events) do
    rhs =
      case events do
        [] -> "(buffered — pending ESC, waiting…)"
        _ -> Enum.map_join(events, ", ", &fmt/1)
      end

    pute(out, "#{String.pad_trailing(label(src), 22)} -> #{rhs}")
  end

  defp label(:timeout), do: "(esc timeout)"

  defp label(data) when is_binary(data) do
    data
    |> :binary.bin_to_list()
    |> Enum.map_join(" ", fn b -> "0x" <> String.pad_leading(Integer.to_string(b, 16), 2, "0") end)
  end

  defp fmt({:char, cp}), do: "{:char, #{cp}} #{inspect(<<cp::utf8>>)}"

  defp fmt({:mouse, m}),
    do: "mouse #{m.action} #{inspect(m.button)} @ (#{m.x},#{m.y}) #{inspect(m.mods)}"

  defp fmt(other), do: inspect(other)

  defp pute(out, str) do
    body = str |> String.trim_trailing("\n") |> String.replace("\n", "\r\n")
    :file.write(out, [body, "\r\n"])
  end

  defp intro(out) do
    pute(out, """
    Vtex smoke test — press keys, watch the events. Ctrl-C to quit.

    Try:
      * plain text and UTF-8 (e.g. é, 日, 🎉)
      * arrows, Home/End, PageUp/PageDown, Insert/Delete
      * function keys F1-F12
      * Alt+<key>  -> {:alt, byte}
      * Escape     -> note the ~#{@esc_timeout_ms}ms pause before :escape (the timeout at work)
      * the mouse  -> click, drag, scroll (SGR mouse reporting is on)
      * paste a block of text
    """)
  end
end
