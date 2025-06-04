defmodule UptimeMonitor.ClusterMonitor do
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    # Subscribe to node connection events
    :net_kernel.monitor_nodes(true)
    
    # Schedule periodic cluster status checks
    Process.send_after(self(), :check_cluster, 5_000)
    
    Logger.info("ClusterMonitor started - monitoring node connections")
    
    {:ok, %{
      connected_nodes: [],
      last_check: DateTime.utc_now()
    }}
  end

  def handle_info({:nodeup, node}, state) do
    Logger.info("✓ Node connected: #{node}")
    new_connected = [node | state.connected_nodes] |> Enum.uniq()
    
    # Notify that we have a new connection
    Phoenix.PubSub.broadcast(
      UptimeMonitor.PubSub,
      "cluster:events",
      {:node_connected, node, DateTime.utc_now()}
    )
    
    {:noreply, %{state | connected_nodes: new_connected}}
  end

  def handle_info({:nodedown, node}, state) do
    Logger.warning("✗ Node disconnected: #{node}")
    new_connected = List.delete(state.connected_nodes, node)
    
    # Notify that we lost a connection
    Phoenix.PubSub.broadcast(
      UptimeMonitor.PubSub,
      "cluster:events",
      {:node_disconnected, node, DateTime.utc_now()}
    )
    
    {:noreply, %{state | connected_nodes: new_connected}}
  end

  def handle_info(:check_cluster, state) do
    current_nodes = Node.list()
    self_node = Node.self()
    
    Logger.info("=== Cluster Status ===")
    Logger.info("Self: #{self_node}")
    Logger.info("Connected nodes: #{inspect(current_nodes)}")
    Logger.info("Total cluster size: #{length(current_nodes) + 1}")
    
    # Schedule next check
    Process.send_after(self(), :check_cluster, 30_000)
    
    {:noreply, %{state | connected_nodes: current_nodes, last_check: DateTime.utc_now()}}
  end

  # Public API to get cluster status
  def get_cluster_status do
    GenServer.call(__MODULE__, :get_status)
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      self_node: Node.self(),
      connected_nodes: Node.list(),
      cluster_size: length(Node.list()) + 1,
      last_check: state.last_check
    }
    {:reply, status, state}
  end
end