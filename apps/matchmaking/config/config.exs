import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n"

config :matchmaking, :upstream_ip, System.fetch_env!("UPSTREAM_IP")
|> String.split(".")
|> Enum.map(&String.to_integer/1)
|> List.to_tuple()

config :matchmaking, :upstream_port, System.get_env("UPSTREAM_PORT", "7777") |> String.to_integer()

config :matchmaking, :inbound_port, System.get_env("INBOUND_PORT", "7777") |> String.to_integer()
config :matchmaking, :outbound_port_start, System.get_env("OUTBOUND_PORT_START", "8000") |> String.to_integer()
config :matchmaking, :outbound_port_end, System.get_env("OUTBOUND_PORT_END", "10000") |> String.to_integer()

config :matchmaking, :recycle_ports_minutes, System.get_env("RECYCLE_PORT_MINUTES", "30") |> String.to_integer()
