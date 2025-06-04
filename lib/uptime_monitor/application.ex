defmodule UptimeMonitor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Set up node name for Railway deployment
    setup_node_name()
    
    # Auto-connect to other nodes for simple distribution (fallback)
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

  defp setup_node_name do
    # Set up distributed node name for Railway
    if railway_private_domain = System.get_env("RAILWAY_PRIVATE_DOMAIN") do
      # Use Railway replica ID if available, otherwise generate a unique ID
      replica_id = System.get_env("RAILWAY_REPLICA_ID") || 
                   System.get_env("RAILWAY_REPLICA_REGION") || 
                   "replica-#{:rand.uniform(1000)}"
      
      node_name = "uptime_monitor_#{replica_id}@#{railway_private_domain}"
      
      # Start EPMD and set the node name
      case System.cmd("epmd", ["-daemon"]) do
        {_, 0} -> 
          IO.puts("EPMD started successfully")
        {_, _} -> 
          IO.puts("EPMD already running or failed to start")
      end
      
      # Configure the node
      case Node.start(String.to_atom(node_name)) do
        {:ok, _} -> 
          IO.puts("Started distributed node: #{node_name}")
        {:error, reason} -> 
          IO.puts("Failed to start distributed node: #{inspect(reason)}")
      end
    else
      IO.puts("RAILWAY_PRIVATE_DOMAIN not set - running in local mode")
    end
  end
end
