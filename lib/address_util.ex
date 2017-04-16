defmodule Shoeboat.AddressUtil do
  def ipfmt({addr, port}) do
    [ip_string(addr), port] |> Enum.join(":")
  end

  defp ip_string(addr) do
    Tuple.to_list(addr) |> Enum.join(".")
  end
end
