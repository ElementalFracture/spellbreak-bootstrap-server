import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n"

config :matchmaking, :outbound_port_start, System.get_env("OUTBOUND_PORT_START", "8000") |> String.to_integer()
config :matchmaking, :outbound_port_end, System.get_env("OUTBOUND_PORT_END", "10000") |> String.to_integer()

config :matchmaking, :recycle_ports_minutes, System.get_env("RECYCLE_PORT_MINUTES", "240") |> String.to_integer()

config :matchmaking, :recording_enabled, System.get_env("RECORDING_ENABLED", "false") == "true"

config :matchmaking, :log_level, System.get_env("LOG_LEVEL", "info")

if System.get_env("UPSTREAM_IP") != nil do
  inbound_port = System.get_env("INBOUND_PORT", "7777") |> String.to_integer()
  server_ip = System.get_env("UPSTREAM_IP", "127.0.0.1")
  server_port = System.get_env("UPSTREAM_PORT", "7777") |> String.to_integer()

  config :matchmaking, :servers, [
    main: {inbound_port, {server_ip, server_port}}
  ]
end

import_config "#{config_env()}.exs"
