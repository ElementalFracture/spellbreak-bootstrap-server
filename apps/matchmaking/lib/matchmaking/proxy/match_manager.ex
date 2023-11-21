defmodule Matchmaking.Proxy.MatchManager do
  use GenServer
  require Logger

  @gproc_prop :matchmaking_match_manager

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl true
  def init(args) do
    {:ok, %{
      server_name: Map.fetch!(args, :server_name),
    }, {:continue, :setup}}
  end

  @impl true
  def handle_continue(:setup, state) do
    :gproc.reg({:p, :l, @gproc_prop})

    {:noreply, state}
  end

  def server_name(pid), do: GenServer.call(pid, :server_name)
  def reset_server(pid), do: GenServer.call(pid, :reset_server)

  @impl true
  def handle_call(:server_name, _, state) do
    {:reply, state.server_name, state}
  end

  @impl true
  def handle_call(:reset_server, _, state) do
    {:reply, :ok, state}
  end

  def gproc_prop, do: @gproc_prop
end
