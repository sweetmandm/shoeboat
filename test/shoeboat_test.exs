defmodule ShoeboatTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, server_pid} = Shoeboat.TCPProxy.start_link(
      4040, "localhost:8080", 5, :client_table)
    {:ok, server_pid: server_pid}
  end

  test "connection", %{server_pid: server_pid} do
    assert {:ok, socket} = :gen_tcp.connect('localhost', 4040,
      [:binary, packet: 0, nodelay: true, active: false])
  end
end
