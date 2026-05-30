defmodule Vtex.PasteTest do
  use ExUnit.Case, async: true
  doctest Vtex.Paste

  alias Vtex.Paste

  test "enable turns bracketed paste on (mode 2004)" do
    assert Paste.enable() =~ "2004h"
  end

  test "disable turns it off" do
    assert Paste.disable() =~ "2004l"
  end
end
