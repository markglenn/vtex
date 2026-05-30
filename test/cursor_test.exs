defmodule Vtex.CursorTest do
  use ExUnit.Case, async: true
  doctest Vtex.Cursor

  alias Vtex.Cursor

  test "absolute position and column" do
    assert Cursor.to(5, 10) == "\e[5;10H"
    assert Cursor.column(3) == "\e[3G"
  end

  test "relative moves in each direction" do
    assert Cursor.move(:up, 2) == "\e[2A"
    assert Cursor.move(:down, 4) == "\e[4B"
    assert Cursor.move(:right) == "\e[1C"
    assert Cursor.move(:left, 7) == "\e[7D"
  end

  test "save/restore and visibility" do
    assert Cursor.save() == "\e7"
    assert Cursor.restore() == "\e8"
    assert Cursor.hide() == "\e[?25l"
    assert Cursor.show() == "\e[?25h"
  end
end
