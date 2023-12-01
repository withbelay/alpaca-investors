import Config

config :alpaca_investors, AlpacaInvestors,
  base_url: "https://broker-api.sandbox.alpaca.markets",
  key: System.get_env("BELAYALPACA__ALPACA_KEY", "key"),
  secret: System.get_env("BELAYALPACA__ALPACA_SECRET", "secret")
