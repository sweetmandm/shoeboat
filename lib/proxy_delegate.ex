require Logger
import Shoeboat.AddressUtil

defmodule Shoeboat.ProxyDelegate do

  def start_proxy_loop(downstream, upstream) do
    {:ok, downstream_peer} = :inet.peername(downstream)
    {:ok, local} = :inet.sockname(downstream)
    Logger.info "Incoming connection from #{ipfmt(downstream_peer)} > #{ipfmt(local)}"
    loop_pid = spawn_link(fn ->
      receive do :ready -> :ok end
      :ok = :inet.setopts(downstream, [:binary, packet: 0, active: true, nodelay: true])
      proxy_loop(downstream, upstream, 0, 0)
    end)
    {:ok, loop_pid}
  end

  defp proxy_loop(downstream_socket, upstream_socket, amount_down, amount_up) do
    receive do
      {:tcp, ^downstream_socket, data} ->
        IO.inspect data
        {:ok, count} = relay_to(upstream_socket, data)
        proxy_loop(downstream_socket, upstream_socket, amount_down + count, amount_up)
      {:tcp_error, ^downstream_socket, reason} ->
        Logger.info "tcp_error downstream #{reason}"
        relay_to(upstream_socket, <<>>)
      {:tcp_closed, ^downstream_socket} ->
        Logger.info "Downstream socket closed"
        relay_to(upstream_socket, <<>>)
        :gen_tcp.close(upstream_socket)
        Logger.info "Total bytes >#{amount_down} <#{amount_up}"
      {:tcp, ^upstream_socket, data} ->
        IO.inspect data
        {:ok, count} = relay_to(downstream_socket, data)
        proxy_loop(downstream_socket, upstream_socket, amount_down, amount_up + count)
      {:tcp_error, ^upstream_socket, reason} ->
        Logger.info "tcp_error upstream #{reason}"
        relay_to(downstream_socket, <<>>)
      {:tcp_closed, ^upstream_socket} ->
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
