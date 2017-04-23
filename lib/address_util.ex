defmodule Shoeboat.AddressUtil do
  def split_host_and_port(input) do
    parts = String.split(input, ":")
    {Enum.at(parts, 0), Enum.at(parts, 1)}
  end

  def ipfmt({addr, port}) do
    parts = [ip_string(addr), port]
    parts |> Enum.join(":")
  end

  defp ip_string(addr) do
    parts = Tuple.to_list(addr)
    parts |> Enum.join(".")
  end
end
