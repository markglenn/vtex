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
end
