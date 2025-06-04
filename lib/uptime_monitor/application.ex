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
      UptimeMonitor.ClusterMonitor,
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
    IO.puts("=== Node Setup Debug ===")
    IO.puts("RAILWAY_PRIVATE_DOMAIN: #{System.get_env("RAILWAY_PRIVATE_DOMAIN")}")
    IO.puts("RAILWAY_REPLICA_ID: #{System.get_env("RAILWAY_REPLICA_ID")}")
    IO.puts("RAILWAY_REPLICA_REGION: #{System.get_env("RAILWAY_REPLICA_REGION")}")
    
    if railway_private_domain = System.get_env("RAILWAY_PRIVATE_DOMAIN") do
      # Use Railway replica region as the unique identifier
      replica_id = System.get_env("RAILWAY_REPLICA_REGION") || 
                   System.get_env("RAILWAY_REPLICA_ID") || 
                   "replica#{:rand.uniform(999)}"
      
      # Clean up replica_id to be DNS-safe
      safe_replica_id = replica_id
                        |> String.replace(~r/[^a-zA-Z0-9-]/, "")
                        |> String.downcase()
      
      node_name = "uptime@#{safe_replica_id}.#{railway_private_domain}"
      
      IO.puts("Attempting to start node: #{node_name}")
      
      # Start EPMD daemon
      case System.cmd("epmd", ["-daemon"]) do
        {_, 0} -> 
          IO.puts("✓ EPMD started successfully")
        {output, code} -> 
          IO.puts("EPMD exit code #{code}: #{output}")
      end
      
      # Configure the node
      case Node.start(String.to_atom(node_name)) do
        {:ok, _} -> 
          IO.puts("✓ Started distributed node: #{node_name}")
          IO.puts("✓ Current node: #{Node.self()}")
        {:error, reason} -> 
          IO.puts("✗ Failed to start distributed node: #{inspect(reason)}")
      end
    else
      IO.puts("RAILWAY_PRIVATE_DOMAIN not set - running in local mode")
    end
  end
end
