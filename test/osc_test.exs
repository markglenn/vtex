defmodule Vtex.OSCTest do
  use ExUnit.Case, async: true
  doctest Vtex.OSC

  alias Vtex.OSC

  test "title wraps the text in OSC 0 ... BEL" do
    assert OSC.title("hello") == "\e]0;hello\a"
  end

  test "hyperlink wraps text with OSC 8 markers around the url" do
    assert OSC.hyperlink("site", "https://example.com") ==
             "\e]8;;https://example.com\asite\e]8;;\a"
  end
end
