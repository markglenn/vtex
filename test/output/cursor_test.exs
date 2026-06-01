defmodule Vtex.Output.CursorTest do
  use ExUnit.Case, async: true
  doctest Vtex.Output.Cursor

  alias Vtex.Output.Cursor

  test "absolute position and column" do
    assert Cursor.to(5, 10) == "\e[5;10H"
    assert Cursor.column(3) == "\e[3G"
  end

  test "relative moves in each direction" do
    assert Cursor.move(:up, 2) == "\e[2A"
    assert Cursor.move(:down, 4) == "\e[4B"
    assert Cursor.move(:right) == "\e[1C"
    assert Cursor.move(:left, 7) == "\e[7D"
    assert Cursor.move(:next_line, 2) == "\e[2E"
    assert Cursor.move(:prev_line) == "\e[1F"
  end

  test "absolute row (VPA)" do
    assert Cursor.row(5) == "\e[5d"
  end

  test "cursor shape (DECSCUSR)" do
    assert Cursor.shape(:block) == "\e[1 q"
    assert Cursor.shape(:block, false) == "\e[2 q"
    assert Cursor.shape(:underline) == "\e[3 q"
    assert Cursor.shape(:underline, false) == "\e[4 q"
    assert Cursor.shape(:bar) == "\e[5 q"
    assert Cursor.shape(:bar, false) == "\e[6 q"
    assert Cursor.reset_shape() == "\e[0 q"
  end

  test "cursor position report request (DSR)" do
    assert Cursor.request_position() == "\e[6n"
  end

  test "save/restore and visibility" do
    assert Cursor.save() == "\e7"
    assert Cursor.restore() == "\e8"
    assert Cursor.hide() == "\e[?25l"
    assert Cursor.show() == "\e[?25h"
  end
end
