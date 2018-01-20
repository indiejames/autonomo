defmodule ReceiverTest do
  use ExUnit.Case
  require Logger
  doctest Mower.Receiver

  test "velocity calculation" do
    assert Mower.Receiver.velocity(2) == 1.0
    assert Mower.Receiver.velocity(1) == -1.0
    assert Mower.Receiver.velocity(1.5) == 0
  end

  test "smooth times" do
    times = [1.0, 1.0]
    assert Mower.Receiver.smooth_times(times) == 1.0
    times = [2.0, 2.0]
    assert Mower.Receiver.smooth_times(times) == 2.0
    times = [2.0, 1.0]
    assert Mower.Receiver.smooth_times(times) == 1.5524861149705065
  end
end