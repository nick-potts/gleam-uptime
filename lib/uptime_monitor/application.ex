defmodule UptimeMonitor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Auto-connect to other nodes for simple distribution
    if connect_to = System.get_env("CONNECT_TO") do
      spawn(fn ->
        :timer.sleep(2000)  # Wait for this node to be ready
        target_node = String.to_atom(connect_to)
        case Node.connect(target_node) do
          true -> IO.puts("Connected to #{target_node}")
          false -> IO.puts("Failed to connect to #{target_node}")
        end
      end)
    end

    children = [
      UptimeMonitorWeb.Telemetry,
      # UptimeMonitor.Repo,  # Disabled - not using database
      {DNSCluster, query: Application.get_env(:uptime_monitor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: UptimeMonitor.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: UptimeMonitor.Finch},
      # Our uptime monitoring components
      UptimeMonitor.StatusTracker,
      UptimeMonitor.DowntimeCoordinator,
      UptimeMonitor.Checker,
      # Start to serve requests, typically the last entry
      UptimeMonitorWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: UptimeMonitor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    UptimeMonitorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
