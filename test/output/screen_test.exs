defmodule Vtex.Output.ScreenTest do
  use ExUnit.Case, async: true
  doctest Vtex.Output.Screen

  alias Vtex.Output.Screen

  test "clearing the screen and lines" do
    assert Screen.clear() == "\e[2J"
    assert Screen.clear_below() == "\e[0J"
    assert Screen.clear_above() == "\e[1J"
    assert Screen.clear_line() == "\e[2K"
    assert Screen.clear_line_end() == "\e[0K"
    assert Screen.clear_line_start() == "\e[1K"
  end

  test "alternate screen buffer" do
    assert Screen.enter_alternate() == "\e[?1049h"
    assert Screen.leave_alternate() == "\e[?1049l"
  end

  test "scroll region" do
    assert Screen.scroll_region(2, 23) == "\e[2;23r"
    assert Screen.reset_scroll_region() == "\e[r"
  end

  test "scrolling the region" do
    assert Screen.scroll_up(3) == "\e[3S"
    assert Screen.scroll_up() == "\e[1S"
    assert Screen.scroll_down(2) == "\e[2T"
    assert Screen.scroll_down() == "\e[1T"
  end

  test "line editing" do
    assert Screen.insert_lines(1) == "\e[1L"
    assert Screen.insert_lines() == "\e[1L"
    assert Screen.delete_lines(2) == "\e[2M"
  end

  test "character editing" do
    assert Screen.insert_chars(2) == "\e[2@"
    assert Screen.delete_chars(2) == "\e[2P"
    assert Screen.erase_chars(4) == "\e[4X"
  end

  test "synchronized updates" do
    assert Screen.begin_sync() == "\e[?2026h"
    assert Screen.end_sync() == "\e[?2026l"
  end

  test "soft and full reset" do
    assert Screen.soft_reset() == "\e[!p"
    assert Screen.full_reset() == "\ec"
  end
end
