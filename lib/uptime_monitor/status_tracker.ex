defmodule UptimeMonitor.StatusTracker do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> 
      %{
        current_status: %{},  # region => :up | :down
        latencies: %{},       # region => latency_ms
        history: []           # [{started_at, ended_at, status, region}, ...]
      }
    end, name: __MODULE__)
  end

  def update_status(region, status) do
    Agent.update(__MODULE__, fn state ->
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
      
      new_state
    end)
  end

  def update_latency(region, latency) do
    Agent.update(__MODULE__, fn state ->
      %{state | latencies: Map.put(state.latencies, region, latency)}
    end)
  end

  def get_current_status do
    Agent.get(__MODULE__, fn state -> state.current_status end)
  end
  
  def get_latencies do
    Agent.get(__MODULE__, fn state -> state.latencies end)
  end

  def get_history(limit \\ 50) do
    Agent.get(__MODULE__, fn state -> 
      state.history
      |> Enum.take(limit)
      |> Enum.map(&format_history_entry/1)
    end)
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