defmodule ReceiverTest do
  use ExUnit.Case
  doctest Mower.Receiver

  test "velocity calculation" do
    assert Mower.Receiver.velocity(2) == 1.0
    assert Mower.Receiver.velocity(1) == -1.0
    assert Mower.Receiver.velocity(1.5) == 0
  end
end
