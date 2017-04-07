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
      opts: [:binary, packet: 0, active: false, reuseaddr: true], 
      proxy_delegate: nil,
      max_clients_allowed: 2
    )
  end

  def init([proxy_delegate, listen_port, max_clients, client_table_name]) do
    Logger.info "init"
    state = %TcpState{
      client_table: :ets.new(:tcp_client_table, [:named_table]),
      listen_port: listen_port, 
      proxy_delegate: proxy_delegate,
      max_clients_allowed: max_clients
    }
    {:ok, state}
  end

  def start_link(proxy_delegate, listen_port, max_clients, client_table_name) do
    Logger.info "start_link"
    result = GenServer.start_link(__MODULE__, [proxy_delegate, listen_port, max_clients, client_table_name], [])
    case result do
      {:ok, server_pid} ->
        start_listen(server_pid, listen_port)
      {:error, {:already_started, old_pid}} ->
        {:ok, old_pid}
      error ->
        IO.inspect error
    end
  end

  def list_clients(server) do
    GenServer.call(server, :list_clients)
  end

  defp start_listen(server_pid, listen_port) do
    result = GenServer.call(server_pid, {:listen, listen_port})
    case result do
      :ok -> 
        start_accept(server_pid)
      error -> 
        IO.inspect error
        error
    end
  end

  defp start_accept(server_pid) do
    case GenServer.call(server_pid, {:accept, server_pid}) do
      :ok ->
        {:ok, server_pid}
      other ->
        IO.inspect other
        other
    end
  end

  def handle_info({:EXIT, accept_pid, reason}, 
                  %TcpState{accept_pid: accept_pid, listen_socket: listen_socket} = state) do
    Logger.error "the accept EXITed"
    server_pid = self()
    accept_pid = spawn_accept_link(server_pid, listen_socket)
    {:noreply, %{state | accept_pid: accept_pid}}
  end

  def handle_info({:DOWN, monitor_ref, _type, _object, _info}, state) do
    Logger.error "the monitored process went DOWN"
    case :ets.member(state.client_table, monitor_ref) do
      true ->
        Logger.info "removing from ets"
        :ets.delete(state.client_table, monitor_ref)
        {:noreply, %{state | client_count: state.client_count - 1}}
      false ->
        Logger.error "was not in ets"
        {:noreply, state}
    end
  end

  def handle_call({:listen, listen_port}, _from, 
                  %TcpState{opts: opts, listen_port: old_port} = state) do
    case :gen_tcp.listen(listen_port, opts) do
      {:ok, listen_socket} ->
        Logger.info "Accepting connections on #{listen_port}"
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
    # Swap in a new 'accept' process, and monitor this one to handle the new connection
    new_accept_pid = spawn_accept_link(server_pid, state.listen_socket)
    Process.unlink(pid)
    case state.client_count < state.max_clients_allowed do
      true ->
        monitor_ref = Process.monitor(pid)
        :ets.insert(state.client_table, {monitor_ref, pid})
        state = %{state |
          accept_pid: new_accept_pid,
          client_count: state.client_count + 1
        }
        Logger.info "client added: #{state.client_count}"
        {:reply, {:ok, state.proxy_delegate}, state}
      false ->
        state = %{state | accept_pid: new_accept_pid}
        Logger.info "Reached max_clients_allowed limit."
        {:reply, {:error, :max_clients_reached, state.proxy_delegate}, state}
    end
  end

  defp spawn_accept_link(server_pid, listen_socket) do
    spawn_link(fn -> accept(server_pid, listen_socket) end)
  end

  def handle_call({:connect_upstream, pid, downstream_socket, server_pid}, _from, %TcpState{} = state) do
    {:ok, pid} = ProxyDelegate.start_link('162.243.32.171', 80, downstream_socket)
    #monitor_ref = Process.monitor(pid)
    case ProxyDelegate.initialize_upstream(pid) do
      {:ok, upstream_socket} ->
        Logger.info "established upstream socket"
        {:ok, proxy_loop_pid} = ProxyDelegate.start_proxy_loop(pid)
        Process.monitor(proxy_loop_pid)
        {:reply, :ok, state} 
      {:error, :closed} ->
        Logger.info "Failed to open upstream socket."
        {:noreply, :ok, state}
      other ->
        Logger.info "ooops"
        other
    end
  end

  defp accept(server_pid, listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, downstream_socket} ->
        case GenServer.call(server_pid, {:connect, self(), downstream_socket, server_pid}) do
          {:ok, proxy_delegate} ->
            Logger.info "about to connect upstream"
            case GenServer.call(server_pid, {:connect_upstream, self(), downstream_socket, server_pid}) do
              :ok ->
                Logger.info "accept processed ok"
              other ->
                Logger.info "accept didn't process ok"
                IO.inspect other
            end
          {:error, :max_clients_reached, proxy_delegate} ->
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
