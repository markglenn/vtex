defmodule Vtex.TokenizerTest do
  use ExUnit.Case, async: true
  doctest Vtex.Tokenizer

  alias Vtex.Tokenizer

  @esc 0x1B
  @bel 0x07

  describe "text" do
    test "plain printable text is a single token" do
      assert Tokenizer.tokenize("hello") == {[{:text, "hello"}], ""}
    end

    test "empty input yields no tokens" do
      assert Tokenizer.tokenize("") == {[], ""}
    end

    test "control bytes stay inside the text run" do
      assert Tokenizer.tokenize("ab\r\n") == {[{:text, "ab\r\n"}], ""}
    end

    test "text is split at an escape sequence" do
      data = <<?a, ?b, @esc, ?[, ?A, ?c>>
      assert Tokenizer.tokenize(data) == {[{:text, "ab"}, {:csi, "", "", ?A}, {:text, "c"}], ""}
    end
  end

  describe "CSI" do
    test "bare final byte" do
      assert Tokenizer.tokenize(<<@esc, ?[, ?A>>) == {[{:csi, "", "", ?A}], ""}
    end

    test "with numeric parameters" do
      assert Tokenizer.tokenize(<<@esc, ?[, "1;31m">>) == {[{:csi, "1;31", "", ?m}], ""}
    end

    test "private-marker prefix is collected as an intermediate" do
      # ESC [ > c  — secondary device attributes; '>' is a private marker.
      assert Tokenizer.tokenize(<<@esc, ?[, ?>, ?c>>) == {[{:csi, "", ">", ?c}], ""}
    end

    test "private marker and parameters split into separate buffers" do
      assert Tokenizer.tokenize(<<@esc, ?[, "?25h">>) == {[{:csi, "25", "?", ?h}], ""}
    end

    test "intermediate bytes are collected separately from parameters" do
      # ESC [ 1 SP q  — DECSCUSR; SP (0x20) is an intermediate byte.
      assert Tokenizer.tokenize(<<@esc, ?[, ?1, 0x20, ?q>>) == {[{:csi, "1", " ", ?q}], ""}
    end
  end

  describe "CSI csi_ignore (malformed sequences are discarded)" do
    test "a colon drops the whole sequence" do
      assert Tokenizer.tokenize(<<@esc, ?[, "38:5:1m">>) == {[], ""}
    end

    test "a parameter byte after an intermediate drops the sequence" do
      # ESC [ SP 1 m  — the '1' after the intermediate SP is out of order.
      assert Tokenizer.tokenize(<<@esc, ?[, 0x20, ?1, ?m>>) == {[], ""}
    end

    test "a private marker after parameters drops the sequence" do
      assert Tokenizer.tokenize(<<@esc, ?[, "25?h">>) == {[], ""}
    end

    test "a high byte (>= 0x80) drops the sequence" do
      assert Tokenizer.tokenize(<<@esc, ?[, ?1, 0x80, ?m>>) == {[], ""}
    end

    test "ground text after a discarded sequence still tokenizes" do
      assert Tokenizer.tokenize(<<@esc, ?[, "3:1m", ?x>>) == {[{:text, "x"}], ""}
    end
  end

  describe "CSI anywhere transitions" do
    @can 0x18
    @sub 0x1A

    test "a C0 control executes in place and the sequence continues" do
      # ESC [ 1 BEL m  — the BEL is emitted as text, then the CSI completes.
      assert Tokenizer.tokenize(<<@esc, ?[, ?1, @bel, ?m>>) ==
               {[{:text, <<@bel>>}, {:csi, "1", "", ?m}], ""}
    end

    test "DEL is ignored inside the body" do
      assert Tokenizer.tokenize(<<@esc, ?[, ?1, 0x7F, ?m>>) == {[{:csi, "1", "", ?m}], ""}
    end

    test "CAN aborts the sequence and returns to ground" do
      assert Tokenizer.tokenize(<<@esc, ?[, ?1, @can, ?x>>) == {[{:text, "x"}], ""}
    end

    test "SUB aborts the sequence and returns to ground" do
      assert Tokenizer.tokenize(<<@esc, ?[, ?1, @sub, ?x>>) == {[{:text, "x"}], ""}
    end

    test "ESC abandons the in-flight sequence and starts a fresh one" do
      # The partial 'ESC [ 1' is dropped; parsing restarts at the second ESC.
      assert Tokenizer.tokenize(<<@esc, ?[, ?1, @esc, ?[, ?A>>) == {[{:csi, "", "", ?A}], ""}
    end

    test "executed C0 controls are kept when ESC restarts" do
      assert Tokenizer.tokenize(<<@esc, ?[, @bel, @esc, ?[, ?A>>) ==
               {[{:text, <<@bel>>}, {:csi, "", "", ?A}], ""}
    end
  end

  describe "SS3" do
    test "always three bytes" do
      assert Tokenizer.tokenize(<<@esc, ?O, ?A>>) == {[{:ss3, ?A}], ""}
    end

    test "consumes only its three bytes, leaving the rest" do
      assert Tokenizer.tokenize(<<@esc, ?O, ?P, ?x>>) == {[{:ss3, ?P}, {:text, "x"}], ""}
    end
  end

  describe "OSC" do
    test "terminated by BEL" do
      data = <<@esc, ?], "0;title", @bel>>
      assert Tokenizer.tokenize(data) == {[{:osc, "0;title"}], ""}
    end

    test "terminated by ST (ESC backslash)" do
      data = <<@esc, ?], "0;title", @esc, ?\\>>
      assert Tokenizer.tokenize(data) == {[{:osc, "0;title"}], ""}
    end

    test "empty payload" do
      assert Tokenizer.tokenize(<<@esc, ?], @bel>>) == {[{:osc, ""}], ""}
    end
  end

  describe "ESC <other>" do
    test "standalone escape" do
      assert Tokenizer.tokenize(<<@esc, ?7>>) == {[{:esc, ?7}], ""}
    end
  end

  describe "rejected string sequences" do
    test "DCS is rejected as invalid" do
      data = <<@esc, ?P, "payload", @esc, ?\\>>
      assert {[{:invalid, invalid}], ""} = Tokenizer.tokenize(data)
      assert invalid == <<@esc, ?P, "payload">>
    end

    test "APC is rejected as invalid" do
      data = <<@esc, ?_, "x", @bel>>
      assert {[{:invalid, <<@esc, ?_, "x">>}], ""} = Tokenizer.tokenize(data)
    end

    test "PM is rejected as invalid" do
      data = <<@esc, ?^, "x", @bel>>
      assert {[{:invalid, <<@esc, ?^, "x">>}], ""} = Tokenizer.tokenize(data)
    end

    test "SOS is rejected as invalid" do
      data = <<@esc, ?X, "x", @bel>>
      assert {[{:invalid, <<@esc, ?X, "x">>}], ""} = Tokenizer.tokenize(data)
    end
  end

  describe "incomplete sequences (returned as leftover)" do
    test "bare ESC" do
      assert Tokenizer.tokenize(<<@esc>>) == {[], <<@esc>>}
    end

    test "ESC [ with no final byte" do
      assert Tokenizer.tokenize(<<@esc, ?[, ?1>>) == {[], <<@esc, ?[, ?1>>}
    end

    test "ESC O with no final byte" do
      assert Tokenizer.tokenize(<<@esc, ?O>>) == {[], <<@esc, ?O>>}
    end

    test "unterminated OSC" do
      data = <<@esc, ?], "title">>
      assert Tokenizer.tokenize(data) == {[], data}
    end

    test "leading tokens are emitted, trailing partial is leftover" do
      data = <<?h, ?i, @esc, ?[>>
      assert Tokenizer.tokenize(data) == {[{:text, "hi"}], <<@esc, ?[>>}
    end
  end
end
