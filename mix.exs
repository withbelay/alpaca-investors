defmodule AlpacaInvestors.MixProject do
  use Mix.Project

  def project do
    [
      app: :alpaca_investors,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:elixir_uuid, "~> 1.2"},
      {:jason, ">= 1.0.0"},
      {:tesla, "~> 1.7"}
    ]
  end
end
