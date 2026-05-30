defmodule Vtex.MouseTest do
  use ExUnit.Case, async: true
  doctest Vtex.Mouse

  alias Vtex.Mouse

  describe "enable/disable" do
    test "enable turns on SGR mode (1006) plus press/release and drag" do
      seq = Mouse.enable()
      assert seq =~ "1000h"
      assert seq =~ "1002h"
      assert seq =~ "1006h"
    end

    test "default (drag) enables 1000 + 1002 + 1006, not 1003" do
      seq = Mouse.enable()
      assert seq =~ "1000h"
      assert seq =~ "1002h"
      assert seq =~ "1006h"
      refute seq =~ "1003h"
    end

    test "motion: :all enables any-event tracking (1003)" do
      seq = Mouse.enable(motion: :all)
      assert seq =~ "1003h"
      assert seq =~ "1006h"
      refute seq =~ "1002h"
    end

    test "motion: :none enables press/release only" do
      seq = Mouse.enable(motion: :none)
      assert seq =~ "1000h"
      assert seq =~ "1006h"
      refute seq =~ "1002h"
      refute seq =~ "1003h"
    end

    test "disable turns every mode off, including 1003" do
      seq = Mouse.disable()
      assert seq =~ "1000l"
      assert seq =~ "1002l"
      assert seq =~ "1003l"
      assert seq =~ "1006l"
    end
  end

  describe "decode buttons and actions" do
    test "left/middle/right press" do
      assert Mouse.decode("0;1;1", ?M).button == :left
      assert Mouse.decode("1;1;1", ?M).button == :middle
      assert Mouse.decode("2;1;1", ?M).button == :right
    end

    test "M is press, m is release" do
      assert Mouse.decode("0;1;1", ?M).action == :press
      assert Mouse.decode("0;1;1", ?m).action == :release
    end

    test "drag (motion + button) vs move (motion, no button)" do
      assert Mouse.decode("32;5;5", ?M) == %{action: :drag, button: :left, x: 5, y: 5, mods: []}
      assert Mouse.decode("35;5;5", ?M) == %{action: :move, button: :none, x: 5, y: 5, mods: []}
    end

    test "wheel up and down" do
      assert Mouse.decode("64;1;1", ?M).button == :wheel_up
      assert Mouse.decode("65;1;1", ?M).button == :wheel_down
      assert Mouse.decode("64;1;1", ?M).action == :press
    end

    test "extra buttons 8-11" do
      assert Mouse.decode("128;1;1", ?M).button == {:button, 8}
      assert Mouse.decode("131;1;1", ?M).button == {:button, 11}
    end
  end

  describe "decode coordinates and modifiers" do
    test "x is column, y is row, both 1-based" do
      assert %{x: 42, y: 7} = Mouse.decode("0;42;7", ?M)
    end

    test "modifier bits: shift=4, alt=8, ctrl=16" do
      assert Mouse.decode("4;1;1", ?M).mods == [:shift]
      assert Mouse.decode("16;1;1", ?M).mods == [:ctrl]
      # left press + shift + ctrl = 0 + 4 + 16 = 20
      assert Mouse.decode("20;1;1", ?M) == %{
               action: :press,
               button: :left,
               x: 1,
               y: 1,
               mods: [:shift, :ctrl]
             }
    end
  end

  describe "malformed input" do
    test "wrong arity or non-numeric params return nil" do
      assert Mouse.decode("0;1", ?M) == nil
      assert Mouse.decode("0;1;1;1", ?M) == nil
      assert Mouse.decode("0;x;1", ?M) == nil
    end

    test "a non-mouse final returns nil" do
      assert Mouse.decode("0;1;1", ?A) == nil
    end
  end
end
