defmodule Shoeboat.AddressUtil do
  def ipfmt(addr, port) do
    [Tuple.to_list(addr) |> Enum.join("."), port] |> Enum.join(":")
  end
end
