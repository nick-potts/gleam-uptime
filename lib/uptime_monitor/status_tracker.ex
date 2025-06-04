defmodule UptimeMonitor.StatusTracker do
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    initial_state = %{
      current_status: %{},  # region => :up | :down
      latencies: %{},       # region => latency_ms
      history: []           # [{started_at, ended_at, status, region}, ...]
    }
    
    # Try to sync state from other cluster nodes
    state = sync_from_cluster() || initial_state
    
    # Monitor node connections to sync when new nodes join
    :net_kernel.monitor_nodes(true)
    
    Logger.info("StatusTracker started with #{length(state.history)} history entries")
    {:ok, state}
  end

  # Try to get state from another node in the cluster
  defp sync_from_cluster do
    case Node.list() do
      [] -> 
        Logger.info("No other nodes found - starting with empty state")
        nil
      nodes ->
        Logger.info("Found cluster nodes: #{inspect(nodes)} - attempting to sync state")
        try_sync_from_nodes(nodes)
    end
  end

  defp try_sync_from_nodes([]), do: nil
  defp try_sync_from_nodes([node | rest]) do
    try do
      case GenServer.call({__MODULE__, node}, :get_full_state, 5000) do
        state when is_map(state) ->
          Logger.info("✓ Synced state from node: #{node}")
          state
        _ ->
          try_sync_from_nodes(rest)
      end
    catch
      _kind, _error ->
        Logger.warning("Failed to sync from node: #{node}")
        try_sync_from_nodes(rest)
    end
  end

  def update_status(region, status) do
    GenServer.cast(__MODULE__, {:update_status, region, status})
  end

  def update_latency(region, latency) do
    GenServer.cast(__MODULE__, {:update_latency, region, latency})
  end

  def get_current_status do
    GenServer.call(__MODULE__, :get_current_status)
  end
  
  def get_latencies do
    GenServer.call(__MODULE__, :get_latencies)
  end

  def get_history(limit \\ 50) do
    GenServer.call(__MODULE__, {:get_history, limit})
  end

  # GenServer callbacks
  def handle_cast({:update_status, region, status}, state) do
    current = Map.get(state.current_status, region)
    IO.puts("StatusTracker: #{region} status update from #{inspect(current)} to #{inspect(status)}")
    
    new_state = if current != status do
      # Status changed - update history
      now = DateTime.utc_now()
      
      # End the previous period if it exists
      history = case find_current_period(state.history, region) do
        nil -> 
          state.history
        {idx, period} ->
          List.replace_at(state.history, idx, %{period | ended_at: now})
      end
      
      # Start new period
      new_period = %{
        started_at: now,
        ended_at: nil,
        status: status,
        region: region
      }
      
      %{state | 
        current_status: Map.put(state.current_status, region, status),
        history: [new_period | history]
      }
    else
      state
    end
    
    {:noreply, new_state}
  end

  def handle_cast({:update_latency, region, latency}, state) do
    new_state = %{state | latencies: Map.put(state.latencies, region, latency)}
    {:noreply, new_state}
  end

  def handle_call(:get_current_status, _from, state) do
    {:reply, state.current_status, state}
  end

  def handle_call(:get_latencies, _from, state) do
    {:reply, state.latencies, state}
  end

  def handle_call({:get_history, limit}, _from, state) do
    history = state.history
              |> Enum.take(limit)
              |> Enum.map(&format_history_entry/1)
    {:reply, history, state}
  end

  def handle_call(:get_full_state, _from, state) do
    {:reply, state, state}
  end

  # Handle node connections - sync state from newly connected nodes
  def handle_info({:nodeup, node}, state) do
    Logger.info("Node connected: #{node} - attempting to sync state")
    
    # Only sync if we have minimal state (new deployment)
    if map_size(state.current_status) == 0 do
      case try_sync_from_nodes([node]) do
        nil -> 
          {:noreply, state}
        synced_state ->
          Logger.info("✓ Synced state from newly connected node: #{node}")
          {:noreply, synced_state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:nodedown, _node}, state) do
    {:noreply, state}
  end

  defp find_current_period(history, region) do
    history
    |> Enum.with_index()
    |> Enum.find(fn {period, _idx} -> 
      period.region == region && is_nil(period.ended_at)
    end)
    |> case do
      {period, idx} -> {idx, period}
      nil -> nil
    end
  end

  defp format_history_entry(entry) do
    duration = if entry.ended_at do
      DateTime.diff(entry.ended_at, entry.started_at, :second)
      |> format_duration()
    else
      "ongoing"
    end
    
    %{
      region: entry.region,
      status: entry.status,
      started_at: entry.started_at,
      duration: duration
    }
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    "#{minutes}m"
  end
  defp format_duration(seconds) do
    hours = div(seconds, 3600)
    minutes = rem(seconds, 3600) |> div(60)
    "#{hours}h #{minutes}m"
  end
end