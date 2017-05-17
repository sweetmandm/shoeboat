require Logger
import Shoeboat.AddressUtil

defmodule Shoeboat.ProxyDelegate do

  def start_proxy_loop(downstream_socket, upstream_socket) do
    {:ok, downstream_peer} = :inet.peername(downstream_socket)
    {:ok, local} = :inet.sockname(downstream_socket)
    Logger.info "Incoming connection from #{ipfmt(downstream_peer)} > #{ipfmt(local)}"
    loop_pid = spawn_link(fn ->
      receive do :ready -> :ok end
      :ok = :inet.setopts(downstream_socket, [:binary, packet: 0, active: true, nodelay: true])
      downstream = %{socket: downstream_socket, amount: 0}
      upstream = %{socket: upstream_socket, amount: 0}
      proxy_loop(downstream, upstream)
    end)
    {:ok, loop_pid}
  end

  defp proxy_loop(downstream, upstream) do
    receive do
      msg -> handle_receive(msg, downstream, upstream)
    end
  end

  defp handle_receive({:tcp, socket, data}, ds = %{socket: socket}, us) do
    IO.inspect data
    {:ok, count} = relay_to(us.socket, data)
    proxy_loop(%{ds | amount: ds.amount + count}, us)
  end

  defp handle_receive({:tcp_error, socket, reason}, %{socket: socket}, us) do
    Logger.info "tcp_error downstream #{reason}"
    relay_to(us.socket, <<>>)
  end

  defp handle_receive({:tcp_closed, socket}, ds = %{socket: socket}, us) do
    Logger.info "Downstream socket closed"
    relay_to(us.socket, <<>>)
    :gen_tcp.close(us.socket)
    Logger.info "Total bytes >#{ds.amount} <#{us.amount}"
  end

  defp handle_receive({:tcp, socket, data}, ds, us = %{socket: socket}) do
    IO.inspect data
    {:ok, count} = relay_to(ds.socket, data)
    proxy_loop(ds, %{us | amount: us.amount + count})
  end

  defp handle_receive({:tcp, socket, data}, ds, us = %{socket: socket}) do
    IO.inspect data
    {:ok, count} = relay_to(ds.socket, data)
    proxy_loop(ds, %{us | amount: us.amount + count})
  end

  defp handle_receive({:tcp_error, socket, reason}, ds, %{socket: socket}) do
    Logger.info "tcp_error upstream #{reason}"
    relay_to(ds.socket, <<>>)
  end

  defp handle_receive({:tcp_closed, socket}, ds, us = %{socket: socket}) do
    Logger.info "Upstream socket closed"
    relay_to(ds.socket, <<>>)
    :gen_tcp.close(ds.socket)
    Logger.info "Total bytes >#{ds.amount} <#{us.amount}"
  end

  defp handle_receive(msg, ds, us) do
    Logger.error "Invalid message:"
    IO.inspect msg
    proxy_loop(ds, us)
  end

  def relay_to(socket, data) do
    :ok = :gen_tcp.send(socket, data)
    {:ok, byte_size(data)}
  end
end
