defmodule Vtex.FocusTest do
  use ExUnit.Case, async: true
  doctest Vtex.Focus

  alias Vtex.Focus

  test "enable turns focus reporting on (mode 1004)" do
    assert Focus.enable() =~ "1004h"
  end

  test "disable turns it off" do
    assert Focus.disable() =~ "1004l"
  end
end
