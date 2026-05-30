defmodule Vtex.InputTest do
  use ExUnit.Case, async: true
  doctest Vtex.Input

  alias Vtex.Input

  describe "text" do
    test "expands to one event per character" do
      assert Input.interpret([{:text, "hi"}]) == [{:char, ?h}, {:char, ?i}]
    end

    test "multi-byte UTF-8 characters stay whole" do
      assert Input.interpret([{:text, "é"}]) == [{:char, ?é}]

      assert Input.interpret([{:text, "café"}]) == [
               {:char, ?c},
               {:char, ?a},
               {:char, ?f},
               {:char, ?é}
             ]

      assert Input.interpret([{:text, "🎉"}]) == [{:char, ?🎉}]
    end

    test "invalid UTF-8 bytes pass through as raw bytes" do
      assert Input.interpret([{:text, <<0xFF>>}]) == [{:char, 0xFF}]
    end

    test "carriage return and newline both become :enter" do
      assert Input.interpret([{:text, "\r"}]) == [:enter]
      assert Input.interpret([{:text, "\n"}]) == [:enter]
    end

    test "DEL and BS both become :backspace" do
      assert Input.interpret([{:text, <<0x7F>>}]) == [:backspace]
      assert Input.interpret([{:text, <<0x08>>}]) == [:backspace]
    end

    test "tab and escape" do
      assert Input.interpret([{:text, "\t"}]) == [:tab]
      assert Input.interpret([{:text, <<0x1B>>}]) == [:escape]
    end

    test "mixed printable and control bytes" do
      assert Input.interpret([{:text, "ab\r"}]) == [{:char, ?a}, {:char, ?b}, :enter]
    end
  end

  describe "arrow keys" do
    test "CSI form (normal cursor mode)" do
      tokens = [{:csi, "", "", ?A}, {:csi, "", "", ?B}, {:csi, "", "", ?C}, {:csi, "", "", ?D}]
      assert Input.interpret(tokens) == [:arrow_up, :arrow_down, :arrow_right, :arrow_left]
    end

    test "SS3 form (application cursor mode)" do
      tokens = [{:ss3, ?A}, {:ss3, ?B}, {:ss3, ?C}, {:ss3, ?D}]
      assert Input.interpret(tokens) == [:arrow_up, :arrow_down, :arrow_right, :arrow_left]
    end
  end

  describe "navigation keys" do
    test "home and end via CSI letters" do
      assert Input.interpret([{:csi, "", "", ?H}, {:csi, "", "", ?F}]) == [:home, :end]
    end

    test "tilde-terminated editing keys" do
      tokens = [
        {:csi, "2", "", ?~},
        {:csi, "3", "", ?~},
        {:csi, "5", "", ?~},
        {:csi, "6", "", ?~},
        {:csi, "1", "", ?~},
        {:csi, "4", "", ?~}
      ]

      assert Input.interpret(tokens) ==
               [:insert, :delete, :page_up, :page_down, :home, :end]
    end
  end

  describe "function keys" do
    test "F1-F4 via SS3" do
      tokens = [{:ss3, ?P}, {:ss3, ?Q}, {:ss3, ?R}, {:ss3, ?S}]

      assert Input.interpret(tokens) ==
               [{:function, 1}, {:function, 2}, {:function, 3}, {:function, 4}]
    end

    test "F5-F12 via tilde sequences" do
      tokens = [
        {:csi, "15", "", ?~},
        {:csi, "17", "", ?~},
        {:csi, "24", "", ?~}
      ]

      assert Input.interpret(tokens) == [{:function, 5}, {:function, 6}, {:function, 12}]
    end
  end

  describe "SGR" do
    test "an m-terminated CSI is parsed into attributes" do
      assert Input.interpret([{:csi, "1;31", "", ?m}]) == [{:sgr, [:bold, {:fg, :red}]}]
    end
  end

  describe "unknown / pass-through" do
    test "an unrecognised CSI final byte passes through" do
      token = {:csi, "", "", ?Z}
      assert Input.interpret([token]) == [{:unknown, token}]
    end

    test "an unrecognised tilde code passes through" do
      token = {:csi, "99", "", ?~}
      assert Input.interpret([token]) == [{:unknown, token}]
    end

    test "a CSI carrying intermediates passes through (e.g. DECSET ESC [ ? 25 h)" do
      token = {:csi, "25", "?", ?h}
      assert Input.interpret([token]) == [{:unknown, token}]
    end

    test "OSC and invalid tokens pass through" do
      osc = {:osc, "0;title"}
      invalid = {:invalid, "x"}
      assert Input.interpret([osc, invalid]) == [{:unknown, osc}, {:unknown, invalid}]
    end

    test "an unrecognised SS3 byte passes through" do
      token = {:ss3, ?Z}
      assert Input.interpret([token]) == [{:unknown, token}]
    end
  end
end
