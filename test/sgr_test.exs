defmodule Vtex.SGRTest do
  use ExUnit.Case, async: true
  doctest Vtex.SGR

  alias Vtex.SGR

  test "empty params default to reset" do
    assert SGR.parse("") == [:reset]
  end

  test "explicit reset" do
    assert SGR.parse("0") == [:reset]
  end

  test "text attributes" do
    assert SGR.parse("1") == [:bold]
    assert SGR.parse("2") == [:faint]
    assert SGR.parse("3") == [:italic]
    assert SGR.parse("4") == [:underline]
    assert SGR.parse("5") == [:blink]
    assert SGR.parse("7") == [:inverse]
  end

  test "basic foreground colors" do
    assert SGR.parse("30") == [{:fg, :black}]
    assert SGR.parse("31") == [{:fg, :red}]
    assert SGR.parse("37") == [{:fg, :white}]
  end

  test "basic background colors" do
    assert SGR.parse("40") == [{:bg, :black}]
    assert SGR.parse("47") == [{:bg, :white}]
  end

  test "bright colors" do
    assert SGR.parse("91") == [{:fg, {:bright, :red}}]
    assert SGR.parse("102") == [{:bg, {:bright, :green}}]
  end

  test "multiple attributes in order" do
    assert SGR.parse("1;4;31") == [:bold, :underline, {:fg, :red}]
  end

  test "256-color palette" do
    assert SGR.parse("38;5;200") == [{:fg, {:index, 200}}]
    assert SGR.parse("48;5;16") == [{:bg, {:index, 16}}]
  end

  test "truecolor" do
    assert SGR.parse("38;2;10;20;30") == [{:fg, {:rgb, 10, 20, 30}}]
    assert SGR.parse("48;2;255;0;128") == [{:bg, {:rgb, 255, 0, 128}}]
  end

  test "extended color combined with other attributes" do
    assert SGR.parse("1;38;5;9;4") == [:bold, {:fg, {:index, 9}}, :underline]
  end

  test "empty sub-parameters are treated as zero (reset)" do
    assert SGR.parse("1;;4") == [:bold, :reset, :underline]
  end

  test "unmapped numeric codes pass through as :unknown" do
    assert SGR.parse("53") == [{:unknown, 53}]
  end

  test "non-numeric parameters are ignored" do
    assert SGR.parse("1;x;4") == [:bold, :underline]
  end
end
