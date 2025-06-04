defmodule UptimeMonitorWeb.TestController do
  use UptimeMonitorWeb, :controller

  def health(conn, %{"status" => status}) do
    case status do
      "up" ->
        conn
        |> put_status(200)
        |> json(%{status: "ok"})
      
      "down" ->
        conn
        |> put_status(503)
        |> json(%{status: "service unavailable"})
        
      "timeout" ->
        # Simulate a timeout
        Process.sleep(15_000)
        conn
        |> put_status(200)
        |> json(%{status: "ok"})
        
      _ ->
        conn
        |> put_status(400)
        |> json(%{error: "Invalid status parameter"})
    end
  end
  
  def health(conn, _params) do
    # Default to up
    conn
    |> put_status(200)
    |> json(%{status: "ok"})
  end
end