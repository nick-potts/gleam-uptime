defmodule UptimeMonitor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      UptimeMonitorWeb.Telemetry,
      UptimeMonitor.Repo,
      {DNSCluster, query: Application.get_env(:uptime_monitor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: UptimeMonitor.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: UptimeMonitor.Finch},
      # Start a worker by calling: UptimeMonitor.Worker.start_link(arg)
      # {UptimeMonitor.Worker, arg},
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
