import Config

config :alpaca_investors, AlpacaInvestors,
  base_url: "https://broker-api.sandbox.alpaca.markets",
  key: System.get_env("BELAYALPACA__ALPACA__KEY", "key"),
  secret: System.get_env("BELAYALPACA__ALPACA__SECRET", "secret")
