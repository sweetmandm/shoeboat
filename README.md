# SHOEBOAT

### An Elixir TCP Proxy

Started by following [this erlang tutorial](http://www.duomark.com/erlang/tutorials/proxy.html) but extended to actually proxy requests to a remote host.

[tcpproxy.ex](https://github.com/sweetmandm/shoeboat/blob/master/lib/tcpproxy.ex) accepts connections and creates/owns the upstream and downstream sockets. It stores a reference of active connections in an ets table.

[proxy_delegate.ex](https://github.com/sweetmandm/shoeboat/blob/master/lib/proxy_delegate.ex) determines what to do with the data when it is received from either the upstream or downstream socket. In this example it just forwards the data and counts the number of bytes that pass up and down.

To run:
```bash
mix run --no-halt mix.exs --listen 4040 --host example.com:80

# try it out
curl --header 'Host: example.com' localhost:4040
```

