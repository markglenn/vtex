defmodule VtexTest do
  use ExUnit.Case, async: true
  doctest Vtex

  alias Vtex.Output.{ANSI, Cursor, Screen}

  test "restore/0 emits the inverse of each setup, alternate buffer last" do
    bytes = IO.iodata_to_binary(Vtex.restore())

    # Each teardown step is present...
    assert bytes =~ ANSI.reset()
    assert bytes =~ Cursor.reset_shape()
    assert bytes =~ Cursor.show()
    assert bytes =~ Screen.reset_scroll_region()
    assert bytes =~ IO.iodata_to_binary(Vtex.Mouse.disable())
    assert bytes =~ Vtex.Paste.disable()
    assert bytes =~ Vtex.Focus.disable()

    # ...and leaving the alternate buffer comes last.
    assert String.ends_with?(bytes, Screen.leave_alternate())
  end
end
