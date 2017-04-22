require ShoeboatTest.RemoteMock
defmodule ShoeboatTest do
  use ExUnit.Case

  setup do
    {:ok, server_pid} = Shoeboat.TCPProxy.start_link(
      4040, "localhost:8080", 5, :client_table)
    ShoeboatTest.RemoteMock.spawn_remote(8080)
    {:ok, server_pid: server_pid}
  end

  test "connection", %{} do
    assert {:ok, _} = :gen_tcp.connect('localhost', 4040,
      [:binary, packet: 0, nodelay: true, active: false])
  end

  test "data send", %{} do
    {:ok, socket} = :gen_tcp.connect('localhost', 4040,
      [:binary, packet: 0, nodelay: true, active: false])
    assert :ok = :gen_tcp.send(socket, <<"Hello">>)
  end

  test "data receive", %{} do
    {:ok, socket} = :gen_tcp.connect('localhost', 4040,
      [:binary, packet: 0, nodelay: true, active: false])
    caller = self()
    spawn_link(fn ->
      assert {:ok, <<"Hi from the remote">>} = :gen_tcp.recv(socket, 0, 1000)
      send(caller, {self(), :ok})
    end)
    assert :ok = :gen_tcp.send(socket, <<"Hello">>)
    assert_receive({_pid, :ok})
  end
end
