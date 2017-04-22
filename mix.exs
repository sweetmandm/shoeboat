defmodule Shoeboat.Mixfile do
  use Mix.Project

  def project do
    [app: :shoeboat,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     aliases: [test: "test --no-start"],
     elixirc_paths: elixirc_paths(Mix.env),
     deps: deps()]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  def application do
    [
      mod: {Shoeboat.Application, []}, 
      extra_applications: [:logger]
    ]
  end

  defp deps do
    []
  end
end
