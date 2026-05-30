defmodule Vtex.ANSITest do
  use ExUnit.Case, async: true
  doctest Vtex.ANSI

  alias Vtex.ANSI

  describe "IO.ANSI parity" do
    test "every 0-arity IO.ANSI sequence function matches byte-for-byte" do
      names =
        for {name, 0} <- IO.ANSI.__info__(:functions),
            name != :enabled?,
            is_binary(apply(IO.ANSI, name, [])),
            do: name

      # Sanity: we actually found the full set, not an empty list.
      assert length(names) > 60

      for name <- names do
        assert apply(ANSI, name, []) == apply(IO.ANSI, name, []),
               "Vtex.ANSI.#{name}/0 does not match IO.ANSI.#{name}/0"
      end
    end

    test "parameterized functions match IO.ANSI" do
      assert ANSI.color(196) == IO.ANSI.color(196)
      assert ANSI.color(5, 0, 0) == IO.ANSI.color(5, 0, 0)
      assert ANSI.color_background(21) == IO.ANSI.color_background(21)
      assert ANSI.color_background(0, 0, 5) == IO.ANSI.color_background(0, 0, 5)
      assert ANSI.cursor(2, 3) == IO.ANSI.cursor(2, 3)
      assert ANSI.cursor_up(4) == IO.ANSI.cursor_up(4)
      assert ANSI.cursor_down(2) == IO.ANSI.cursor_down(2)
      assert ANSI.cursor_left(1) == IO.ANSI.cursor_left(1)
      assert ANSI.cursor_right(9) == IO.ANSI.cursor_right(9)
    end

    test "format and format_fragment match IO.ANSI (with emit? = true)" do
      cases = [
        [:red, :bright, "hi"],
        [:red, "hi"],
        ["plain"],
        [:clear, :home, "x"]
      ]

      for data <- cases do
        assert bin(ANSI.format(data)) == bin(IO.ANSI.format(data, true))
        assert bin(ANSI.format_fragment(data)) == bin(IO.ANSI.format_fragment(data, true))
      end

      assert bin(ANSI.format([:red, "hi"], false)) == bin(IO.ANSI.format([:red, "hi"], false))
    end

    test "an unknown format atom raises, like IO.ANSI" do
      assert_raise ArgumentError, fn -> ANSI.format([:not_a_real_attr]) end
    end
  end

  describe "beyond IO.ANSI" do
    test "24-bit truecolor" do
      assert ANSI.true_color(255, 128, 0) == "\e[38;2;255;128;0m"
      assert ANSI.true_color_background(10, 20, 30) == "\e[48;2;10;20;30m"
    end
  end

  defp bin(iodata), do: IO.iodata_to_binary(iodata)
end
