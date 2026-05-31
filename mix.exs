defmodule Vtex.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/markglenn/vtex"

  def project do
    [
      app: :vtex,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        # :mix is needed because the dev-only vtex.smoke task is a Mix.Task.
        plt_add_apps: [:mix]
      ],
      name: "Vtex",
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    # A pure library: no processes, no logging, no runtime applications.
    [extra_applications: []]
  end

  # `dev/` holds development-only code (e.g. the `vtex.smoke` task) that is
  # compiled in dev but never shipped — it is not in the package `files`.
  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:stream_data, "~> 1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end

  # `mix lint` runs the static analysers together.
  defp aliases do
    [lint: ["credo --strict", "dialyzer"]]
  end

  defp description do
    "A streaming VT/ANSI escape-sequence library for SSH/Telnet game servers, " <>
      "BBS engines and MUD frameworks: parse terminal input into semantic events " <>
      "and build the control sequences to draw the screen."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @source_url <> "/blob/main/CHANGELOG.md"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "guides/integration.md", "CHANGELOG.md"],
      groups_for_modules: [
        Input: [Vtex.Input, Vtex.Input.Stream, Vtex.Input.Tokenizer],
        Output: [Vtex.Output.ANSI, Vtex.Output.Cursor, Vtex.Output.Screen, Vtex.Output.OSC],
        "Both directions": [Vtex.SGR, Vtex.Mouse, Vtex.Paste, Vtex.Focus]
      ]
    ]
  end
end
