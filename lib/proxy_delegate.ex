require Logger
import Shoeboat.AddressUtil

defmodule Shoeboat.ProxyDelegate do
  alias Shoeboat.ProxyDelegate

  def start_proxy_loop(pid, downstream, upstream) do
    {:ok, {s_addr, s_port}} = :inet.peername(downstream)
    {:ok, {d_addr, d_port}} = :inet.sockname(downstream)
    Logger.info "Incoming connection from #{ipfmt(s_addr, s_port)} #{ipfmt(d_addr, d_port)}"
    loop_pid = spawn_link(fn ->
      receive do :ready -> :ok end
      :ok = :inet.setopts(downstream, [:binary, packet: 0, active: true, nodelay: true])
      proxy_loop(downstream, upstream)
    end)
    {:ok, loop_pid}
  end

  defp proxy_loop(downstream_socket, upstream_socket) do
    receive do
      {:tcp, socket, data} when socket == downstream_socket ->
        IO.inspect data
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
        IO.inspect data
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
