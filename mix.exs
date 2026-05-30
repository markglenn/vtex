defmodule Vtex.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/markglenn/vtex"

  def project do
    [
      app: :vtex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Vtex",
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "A streaming VT/ANSI escape-sequence tokenizer for SSH/Telnet game servers, " <>
      "BBS engines and MUD frameworks. Input parsing only — the Elixir equivalent " <>
      "of the Rust `vte` crate."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "Vtex",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
