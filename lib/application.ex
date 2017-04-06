defmodule Shoeboat.Application do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      worker(Shoeboat.TCPProxy, [nil, 4040, 2, :tcp_proxy_clients])
    ]

    opts = [strategy: :one_for_one, name: Shoeboat.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
