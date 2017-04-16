require Logger
require Shoeboat.ProxyDelegate

defmodule Shoeboat.TCPProxy do
  use GenServer
  alias Shoeboat.ProxyDelegate

  defmodule TcpState do
    defstruct(
      accept_pid: nil,
      client_count: 0,
      client_table: nil, 
      listen_port: 8000, 
      listen_socket: nil, 
      remote_host: nil,
      opts: [:binary, packet: 0, active: false, reuseaddr: true], 
      max_clients_allowed: 2
    )
  end

  def init([listen_port, remote_host, max_clients, client_table_name]) do
    state = %TcpState{
      client_table: :ets.new(client_table_name, [:named_table]),
      listen_port: listen_port, 
      remote_host: remote_host,
      max_clients_allowed: max_clients
    }
    {:ok, state}
  end

  def start_link(listen_port, remote_host, max_clients, client_table_name) do
    result = GenServer.start_link(__MODULE__, [listen_port, remote_host, max_clients, client_table_name], [])
    case result do
      {:ok, server_pid} ->
        start_listen(server_pid, listen_port)
      {:error, {:already_started, old_pid}} ->
        {:ok, old_pid}
      error ->
        IO.inspect error
    end
  end

  defp start_listen(server_pid, listen_port) do
    :ok = GenServer.call(server_pid, {:listen, listen_port})
    start_accept(server_pid)
  end

  defp start_accept(server_pid) do
    :ok = GenServer.call(server_pid, {:accept, server_pid})
    {:ok, server_pid}
  end

  def handle_info({:EXIT, accept_pid, _reason},
                  %TcpState{accept_pid: accept_pid, listen_socket: listen_socket} = state) do
    Logger.error "the accept EXITed"
    server_pid = self()
    accept_pid = spawn_accept_link(server_pid, listen_socket)
    {:noreply, %{state | accept_pid: accept_pid}}
  end

  def handle_info({:DOWN, monitor_ref, _type, _object, _info}, state) do
    case :ets.member(state.client_table, monitor_ref) do
      true ->
        :ets.delete(state.client_table, monitor_ref)
        {:noreply, %{state | client_count: state.client_count - 1}}
      false ->
        Logger.error "This monitored process was not in ets"
        {:noreply, state}
    end
  end

  def handle_call({:listen, listen_port}, _from, 
                  %TcpState{opts: opts, listen_port: old_port, remote_host: host} = state) do
    case :gen_tcp.listen(listen_port, opts) do
      {:ok, listen_socket} ->
        Logger.info "Accepting connections on #{listen_port}"
        Logger.info "Proxying to #{host}"
        state = %{state |
          listen_port: listen_port,
          listen_socket: listen_socket
        }
        cond do
          old_port == nil or old_port == listen_port ->
            {:reply, :ok, state}
          true ->
            # Close out the prior port.
            :ets.delete_all_objects(state.client_table)
            :gen_tcp.close(old_port)
            {:reply, :ok, %{state | client_count: 0}}
        end
      {:error, :eaddrinuse} ->
        Logger.info "Hm. It's already in use."
        {:stop, :not_ok, state}
      other ->
        IO.inspect other
        {:stop, :not_ok, state}
    end
  end

  def handle_call({:accept, server_pid}, _from, 
                  %TcpState{listen_socket: listen_socket} = state) do
    accept_pid = spawn_accept_link(server_pid, listen_socket)
    {:reply, :ok, %{state | accept_pid: accept_pid}}
  end

  def handle_call({:connect, pid, _upstream_socket, server_pid}, _from,
                  %TcpState{accept_pid: pid} = state) do
    new_accept_pid = spawn_accept_link(server_pid, state.listen_socket)
    case state.client_count < state.max_clients_allowed do
      true ->
        state = %{state |
          accept_pid: new_accept_pid,
          client_count: state.client_count + 1
        }
        Logger.info "client added: #{state.client_count}"
        {:reply, :ok, state}
      false ->
        state = %{state | accept_pid: new_accept_pid}
        Logger.info "Reached max_clients_allowed limit."
        {:reply, {:error, :max_clients_reached}, state}
    end
  end

  def handle_call({:connect_upstream, downstream_socket}, _from, %TcpState{remote_host: remote_host} = state) do
    host = String.split(remote_host, ":")
    {:ok, upstream_socket} = initialize_upstream(Enum.at(host, 0), Enum.at(host, 1))
    {:ok, proxy_loop_pid} = ProxyDelegate.start_proxy_loop(downstream_socket, upstream_socket)
    :gen_tcp.controlling_process(downstream_socket, proxy_loop_pid)
    :gen_tcp.controlling_process(upstream_socket, proxy_loop_pid)
    send(proxy_loop_pid, :ready)
    monitor_ref = Process.monitor(proxy_loop_pid)
    :ets.insert(state.client_table, {monitor_ref, proxy_loop_pid})
    {:reply, :ok, state}
  end

  defp spawn_accept_link(server_pid, listen_socket) do
    spawn_link(fn -> accept(server_pid, listen_socket) end)
  end

  defp initialize_upstream(dest_addr, dest_port) do
    :gen_tcp.connect(
      String.to_char_list(dest_addr),
      String.to_integer(dest_port),
      [:binary, packet: 0, nodelay: true, active: true])
  end

  defp accept(server_pid, listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, downstream_socket} ->
        case GenServer.call(server_pid, {:connect, self(), downstream_socket, server_pid}) do
          :ok ->
            :gen_tcp.controlling_process(downstream_socket, server_pid)
            :ok = GenServer.call(server_pid, {:connect_upstream, downstream_socket})
          {:error, :max_clients_reached} ->
            :gen_tcp.recv(downstream_socket, 0, 1000)
            :gen_tcp.close(downstream_socket)
          other ->
            IO.inspect other
            other
        end
      {:error, reason} ->
        Logger.info "gen_tcp accept failed: #{reason}"
    end
  end
end
