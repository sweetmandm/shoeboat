defmodule Shoeboat.Application do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec
    {opts, _argv, _errors} = OptionParser.parse(System.argv, strict: [listen: :integer, host: :string])

    children = [
      worker(Shoeboat.TCPProxy, [
        opts[:listen] || 4040,
        opts[:host] || "example.com:80",
        2,
        :tcp_proxy_clients])
    ]

    opts = [strategy: :one_for_one, name: Shoeboat.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
