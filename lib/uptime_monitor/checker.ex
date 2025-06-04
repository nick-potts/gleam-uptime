defmodule UptimeMonitor.Checker do
  use GenServer
  require Logger

  # 5 seconds
  @check_interval 5_000
  @timeout 10_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    # Schedule first check
    Process.send_after(self(), :check, 1_000)
    
    region = System.get_env("RAILWAY_REPLICA_REGION", "local")
    target_url = System.get_env("TARGET_URL", "https://ordereditor.app/health")
    Logger.info("Starting checker for region: #{region}, monitoring: #{target_url}")

    {:ok,
     %{
       status: :unknown,
       pending_count: 0,
       region: region
     }}
  end

  def handle_info(:check, state) do
    # Perform the check
    new_state =
      case check_endpoint() do
        {:up, latency} ->
          # Report success to coordinator
          UptimeMonitor.DowntimeCoordinator.report_success(state.region)
          
          # Update status tracker
          UptimeMonitor.StatusTracker.update_status(state.region, :up)
          UptimeMonitor.StatusTracker.update_latency(state.region, latency)
          
          # Broadcast region-specific status
          broadcast_region_status(:up, state.region, latency)
          
          %{state | status: :up, pending_count: 0}

        {:down, _} ->
          case state.status do
            :up ->
              # First failure for this checker
              Logger.warning("Region #{state.region}: Endpoint check failed - pending local confirmation")
              %{state | status: :pending, pending_count: 1}

            :pending ->
              # Second failure for this checker - report to coordinator
              Logger.error("Region #{state.region}: Endpoint check failed twice - reporting to coordinator")
              UptimeMonitor.DowntimeCoordinator.report_failure(state.region)
              UptimeMonitor.StatusTracker.update_status(state.region, :down)
              broadcast_region_status(:down, state.region, nil)
              %{state | status: :down, pending_count: 0}

            :down ->
              # Still down - keep reporting
              UptimeMonitor.DowntimeCoordinator.report_failure(state.region)
              state

            :unknown ->
              # Initial failure
              %{state | status: :pending, pending_count: 1}
          end
      end

    # Schedule next check
    Process.send_after(self(), :check, @check_interval)

    {:noreply, new_state}
  end

  defp check_endpoint do
    target_url = System.get_env("TARGET_URL", "https://ordereditor.app/health")
    
    start_time = System.monotonic_time(:millisecond)
    
    result = case Finch.build(:get, target_url)
         |> Finch.request(UptimeMonitor.Finch, receive_timeout: @timeout) do
      {:ok, %{status: status}} when status >= 200 and status < 300 ->
        latency = System.monotonic_time(:millisecond) - start_time
        Logger.debug("Check successful: #{status}, latency: #{latency}ms")
        {:up, latency}

      {:ok, %{status: status}} ->
        Logger.debug("Check failed with status: #{status}")
        {:down, nil}
        
      {:error, reason} ->
        Logger.debug("Check error: #{inspect(reason)}")
        {:down, nil}
    end
    
    result
  end

  defp broadcast_region_status(status, region, latency) do
    Phoenix.PubSub.broadcast(
      UptimeMonitor.PubSub,
      "uptime:status",
      {:region_status, status, region, latency}
    )
  end
end
