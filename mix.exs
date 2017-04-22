defmodule Shoeboat.Mixfile do
  use Mix.Project

  def project do
    [app: :shoeboat,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     aliases: [test: "test --no-start"],
     deps: deps()]
  end

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
