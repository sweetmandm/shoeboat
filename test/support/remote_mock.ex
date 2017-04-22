defmodule ShoeboatTest.RemoteMock do
  def spawn_remote(port) do
    spawn_link(fn -> start_remote(port) end)
  end

  def start_remote(port) do
    {:ok, listen_socket} = :gen_tcp.listen(port,
      [:binary, packet: 0, active: false, reuseaddr: true])
    {:ok, socket} = :gen_tcp.accept(listen_socket)
    case :gen_tcp.recv(socket, 0, 1000) do
      {:ok, <<"Hello">>} ->
        :gen_tcp.send(socket, <<"Hi from the remote">>)
      any ->
        :gen_tcp.send(socket, any)
    end
  end
end
