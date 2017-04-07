require Logger

defmodule Shoeboat.ProxyDelegate do
  alias Shoeboat.ProxyDelegate

  def start_link(dest_addr, dest_port, downstream_socket) do
    state = %{
      dest_addr: dest_addr, 
      dest_port: dest_port, 
      downstream_socket: downstream_socket
    }
    :gen_tcp.controlling_process(downstream_socket, self())
    Agent.start_link(fn -> state end)
  end

  def dest_addr(pid) do
    Agent.get(pid, &Map.get(&1, :dest_addr))
  end

  def dest_port(pid) do
    Agent.get(pid, &Map.get(&1, :dest_port))
  end

  def upstream_socket(pid) do
    Agent.get(pid, &Map.get(&1, :upstream_socket))
  end

  def downstream_socket(pid) do
    Agent.get(pid, &Map.get(&1, :downstream_socket))
  end

  def initialize_upstream(pid) do
    case :gen_tcp.connect('localhost', #ProxyDelegate.dest_addr(pid), 
                          3000, #ProxyDelegate.dest_port(pid),
                          [:binary, packet: 0, nodelay: true, active: true]) do
      {:ok, upstream_socket} ->
        Agent.update(pid, &Map.put(&1, :upstream_socket, upstream_socket))
        IO.inspect upstream_socket
        {:ok, upstream_socket}
      other ->
        Logger.info "someting else #{other}"
        other
    end
  end

  def start_proxy_loop(pid) do
    upstream_socket = ProxyDelegate.upstream_socket(pid)
    downstream_socket = ProxyDelegate.downstream_socket(pid)
    :ok = :inet.setopts(downstream_socket, [:binary, packet: 0, active: true, reuseaddr: true])
    pid = spawn_link(fn ->
      proxy_loop(downstream_socket, upstream_socket)
    end)
    Process.monitor(pid)
    if downstream_socket do :gen_tcp.controlling_process(downstream_socket, pid) end
    if upstream_socket do :gen_tcp.controlling_process(upstream_socket, pid) end
    {:ok, pid}
  end

  defp proxy_loop(downstream_socket, upstream_socket) do
    receive do
      {:tcp, socket, data} when socket == downstream_socket ->
        Logger.info "tcp downstream"
        Logger.info data
        relay_downstream(upstream_socket, data)
        proxy_loop(downstream_socket, upstream_socket)
      {:tcp_error, socket, reason} when socket == downstream_socket ->
        Logger.info "tcp_error downstream #{reason}"
        relay_downstream(upstream_socket, <<>>)
      {:tcp_closed, socket} when socket == downstream_socket ->
        Logger.info "Downstream socket closed"
        relay_downstream(upstream_socket, <<>>)
        :gen_tcp.close(upstream_socket)
      {:tcp, socket, data} when socket == upstream_socket ->
        Logger.info "tcp upstream"
        relay_upstream(downstream_socket, data)
        proxy_loop(downstream_socket, upstream_socket)
      {:tcp_error, socket, reason} when socket == upstream_socket ->
        Logger.info "tcp_error upstream #{reason}"
        relay_upstream(downstream_socket, <<>>)
      {:tcp_closed, socket} when socket == upstream_socket ->
        Logger.info "Upstream socket closed"
        relay_upstream(downstream_socket, <<>>)
        :gen_tcp.close(downstream_socket)
      other ->
        Logger.error "Invalid message:"
        IO.inspect other
        proxy_loop(downstream_socket, upstream_socket)
    end
  end

  def relay_upstream(downstream_socket, data) do
    :gen_tcp.send(downstream_socket, data)
  end

  def relay_downstream(upstream_socket, data) do
    :gen_tcp.send(upstream_socket, data)
  end
end
