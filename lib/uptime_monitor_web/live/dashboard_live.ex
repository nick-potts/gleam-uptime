defmodule UptimeMonitorWeb.DashboardLive do
  use UptimeMonitorWeb, :live_view
  
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(UptimeMonitor.PubSub, "uptime:status")
    end
    
    socket = assign(socket,
      status: UptimeMonitor.StatusTracker.get_current_status(),
      latencies: UptimeMonitor.StatusTracker.get_latencies(),
      history: UptimeMonitor.StatusTracker.get_history()
    )
    
    {:ok, socket}
  end
  
  # Region-specific status update (not confirmed globally)
  def handle_info({:region_status, status, region, latency}, socket) do
    # Update the region's individual status and latency
    UptimeMonitor.StatusTracker.update_status(region, status)
    if latency, do: UptimeMonitor.StatusTracker.update_latency(region, latency)
    
    socket = assign(socket,
      status: UptimeMonitor.StatusTracker.get_current_status(),
      latencies: UptimeMonitor.StatusTracker.get_latencies(),
      history: UptimeMonitor.StatusTracker.get_history()
    )
    
    {:noreply, socket}
  end
  
  # Confirmed status change (multiple regions agree)
  def handle_info({:confirmed_status_change, status, _timestamp}, socket) do
    # Update all regions to the confirmed status
    regions = Map.keys(socket.assigns.status)
    Enum.each(regions, fn region ->
      UptimeMonitor.StatusTracker.update_status(region, status)
    end)
    
    socket = assign(socket,
      status: UptimeMonitor.StatusTracker.get_current_status(),
      history: UptimeMonitor.StatusTracker.get_history()
    )
    
    {:noreply, socket}
  end
  
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto p-6">
      <h1 class="text-3xl font-bold mb-8">Uptime Monitor</h1>
      
      <div class="mb-8">
        <h2 class="text-xl font-semibold mb-4">Current Status</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <%= if map_size(@status) == 0 do %>
            <div class="p-4 bg-gray-100 rounded">
              <p class="text-gray-500">No regions reporting yet...</p>
            </div>
          <% else %>
            <%= for {region, status} <- @status do %>
              <div class={"p-4 rounded-lg border-2 " <> status_color(status)}>
                <h3 class="font-semibold"><%= region %></h3>
                <p class="text-2xl mt-2"><%= status_text(status) %></p>
                <%= if latency = Map.get(@latencies, region) do %>
                  <p class="text-sm mt-1 opacity-75"><%= latency %>ms</p>
                <% end %>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
      
      <div>
        <h2 class="text-xl font-semibold mb-4">History</h2>
        <div class="bg-white rounded-lg shadow overflow-hidden">
          <table class="min-w-full">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Region
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Status
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Started At
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Duration
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= for entry <- @history do %>
                <tr>
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    <%= entry.region %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm">
                    <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full " <> status_badge(entry.status)}>
                      <%= status_text(entry.status) %>
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <%= Calendar.strftime(entry.started_at, "%Y-%m-%d %H:%M:%S UTC") %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <%= entry.duration %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end
  
  defp status_color(:up), do: "bg-green-100 border-green-500 text-green-900"
  defp status_color(:down), do: "bg-red-100 border-red-500 text-red-900"
  defp status_color(_), do: "bg-gray-100 border-gray-300 text-gray-700"
  
  defp status_badge(:up), do: "bg-green-100 text-green-800"
  defp status_badge(:down), do: "bg-red-100 text-red-800"
  defp status_badge(_), do: "bg-gray-100 text-gray-800"
  
  defp status_text(:up), do: "UP"
  defp status_text(:down), do: "DOWN"
  defp status_text(_), do: "UNKNOWN"
end