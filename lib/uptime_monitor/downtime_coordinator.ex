defmodule UptimeMonitor.DowntimeCoordinator do
  use GenServer
  require Logger

  @confirmation_window 10_000  # 10 seconds to get confirmation from another replica

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    # Subscribe to coordination messages from other instances
    Phoenix.PubSub.subscribe(UptimeMonitor.PubSub, "coordination:failures")
    Phoenix.PubSub.subscribe(UptimeMonitor.PubSub, "coordination:successes")
    
    {:ok, %{
      pending_failures: %{},  # region => {timestamp, timer_ref}
      confirmed_down: false
    }}
  end

  # Called when a region detects the endpoint is down
  def report_failure(region) do
    GenServer.cast(__MODULE__, {:failure_detected, region})
  end

  # Called when a region detects the endpoint is up
  def report_success(region) do
    GenServer.cast(__MODULE__, {:success_detected, region})
  end

  def handle_cast({:failure_detected, region}, state) do
    Logger.info("Failure detected by region: #{region}")
    
    # Broadcast this failure to other instances
    Phoenix.PubSub.broadcast(
      UptimeMonitor.PubSub,
      "coordination:failures",
      {:remote_failure_detected, region, node()}
    )
    
    new_state = case map_size(state.pending_failures) do
      0 ->
        # First failure - start confirmation timer
        timer_ref = Process.send_after(self(), {:timeout, region}, @confirmation_window)
        %{state | pending_failures: Map.put(state.pending_failures, region, {DateTime.utc_now(), timer_ref})}
      
      _ ->
        # Another region confirmed - mark as down!
        if not state.confirmed_down do
          Logger.error("Endpoint DOWN confirmed by multiple regions")
          broadcast_confirmed_status(:down)
          
          # Cancel all timers
          state.pending_failures
          |> Map.values()
          |> Enum.each(fn {_, timer_ref} -> Process.cancel_timer(timer_ref) end)
          
          %{state | confirmed_down: true, pending_failures: %{}}
        else
          state
        end
    end
    
    {:noreply, new_state}
  end

  def handle_cast({:success_detected, region}, state) do
    Logger.info("Success detected by region: #{region}")
    
    # Broadcast this success to other instances
    Phoenix.PubSub.broadcast(
      UptimeMonitor.PubSub,
      "coordination:successes",
      {:remote_success_detected, region, node()}
    )
    
    # Clear any pending failure for this region
    new_pending = case Map.get(state.pending_failures, region) do
      {_, timer_ref} ->
        Process.cancel_timer(timer_ref)
        Map.delete(state.pending_failures, region)
      nil ->
        state.pending_failures
    end
    
    # If we were down and now have success, mark as up
    new_state = if state.confirmed_down do
      Logger.info("Endpoint is back UP")
      broadcast_confirmed_status(:up)
      %{state | confirmed_down: false, pending_failures: new_pending}
    else
      %{state | pending_failures: new_pending}
    end
    
    {:noreply, new_state}
  end

  def handle_info({:timeout, region}, state) do
    # Single region timeout - not confirmed by others
    Logger.warning("Failure from #{region} not confirmed by other regions")
    
    new_pending = Map.delete(state.pending_failures, region)
    {:noreply, %{state | pending_failures: new_pending}}
  end

  # Handle remote failure reports from other instances
  def handle_info({:remote_failure_detected, region, from_node}, state) do
    Logger.info("Remote failure detected by region: #{region} from node: #{from_node}")
    
    # Treat this as a local failure detection to trigger coordination
    new_state = case map_size(state.pending_failures) do
      0 ->
        # First failure - start confirmation timer
        timer_ref = Process.send_after(self(), {:timeout, region}, @confirmation_window)
        %{state | pending_failures: Map.put(state.pending_failures, region, {DateTime.utc_now(), timer_ref})}
      
      _ ->
        # Another region confirmed - mark as down!
        if not state.confirmed_down do
          Logger.error("Endpoint DOWN confirmed by multiple regions (including remote)")
          broadcast_confirmed_status(:down)
          
          # Cancel all timers
          state.pending_failures
          |> Map.values()
          |> Enum.each(fn {_, timer_ref} -> Process.cancel_timer(timer_ref) end)
          
          %{state | confirmed_down: true, pending_failures: %{}}
        else
          state
        end
    end
    
    {:noreply, new_state}
  end

  # Handle remote success reports from other instances
  def handle_info({:remote_success_detected, region, from_node}, state) do
    Logger.info("Remote success detected by region: #{region} from node: #{from_node}")
    
    # Clear any pending failure for this region
    new_pending = case Map.get(state.pending_failures, region) do
      {_, timer_ref} ->
        Process.cancel_timer(timer_ref)
        Map.delete(state.pending_failures, region)
      nil ->
        state.pending_failures
    end
    
    # If we were down and now have success, mark as up
    new_state = if state.confirmed_down do
      Logger.info("Endpoint is back UP (confirmed by remote)")
      broadcast_confirmed_status(:up)
      %{state | confirmed_down: false, pending_failures: new_pending}
    else
      %{state | pending_failures: new_pending}
    end
    
    {:noreply, new_state}
  end

  defp broadcast_confirmed_status(status) do
    Phoenix.PubSub.broadcast(
      UptimeMonitor.PubSub,
      "uptime:status",
      {:confirmed_status_change, status, DateTime.utc_now()}
    )
  end
end