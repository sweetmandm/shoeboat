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
      proxy_loop(downstream, upstream, 0, 0)
    end)
    {:ok, loop_pid}
  end

  defp proxy_loop(downstream_socket, upstream_socket, amount_down, amount_up) do
    receive do
      {:tcp, socket, data} when socket == downstream_socket ->
        IO.inspect data
        {:ok, count} = relay_to(upstream_socket, data)
        proxy_loop(downstream_socket, upstream_socket, amount_down + count, amount_up)
      {:tcp_error, socket, reason} when socket == downstream_socket ->
        Logger.info "tcp_error downstream #{reason}"
        relay_to(upstream_socket, <<>>)
      {:tcp_closed, socket} when socket == downstream_socket ->
        Logger.info "Downstream socket closed"
        relay_to(upstream_socket, <<>>)
        :gen_tcp.close(upstream_socket)
        Logger.info "Total bytes >#{amount_down} <#{amount_up}"
      {:tcp, socket, data} when socket == upstream_socket ->
        IO.inspect data
        {:ok, count} = relay_to(downstream_socket, data)
        proxy_loop(downstream_socket, upstream_socket, amount_down, amount_up + count)
      {:tcp_error, socket, reason} when socket == upstream_socket ->
        Logger.info "tcp_error upstream #{reason}"
        relay_to(downstream_socket, <<>>)
      {:tcp_closed, socket} when socket == upstream_socket ->
        Logger.info "Upstream socket closed"
        relay_to(downstream_socket, <<>>)
        :gen_tcp.close(downstream_socket)
        Logger.info "Total bytes >#{amount_down} <#{amount_up}"
      other ->
        Logger.error "Invalid message:"
        IO.inspect other
        proxy_loop(downstream_socket, upstream_socket, amount_down, amount_up)
    end
  end

  def relay_to(socket, data) do
    :ok = :gen_tcp.send(socket, data)
    {:ok, byte_size(data)}
  end
end
