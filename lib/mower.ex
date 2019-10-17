defmodule Mower do
  require Binary
  use Bitwise, only_operators: true
  use Constants
  alias ElixirALE.SPI
  alias ElixirALE.GPIO
  require Logger

  @doc """
  Calculates two byte binary representing the SPI command to set the DAC to the
  output voltage corresponding to a given velocity
  """

  def command_for_speed(speed) when speed <= @max_speed do
    # set the configuration bits
    Binary.from_integer(@configuration_bits ||| speed)
  end

  def command_for_speed(_speed) do
    throw("Maximum motor speed exceeded")
  end

  # Set the speed of the controller associated with the given pid.
  # Speed must be in the range 0 to 1.
  defp set_speed(pid, speed) when speed >= 0 and speed <= 1 do
    spd = round(@speed_weight * speed * @max_speed)
    SPI.transfer(pid, command_for_speed(spd))
  end

  defp set_speed(_pid, _speed) do
    throw("Speed must be in the range 0 to 1")
  end

  # Set the motor direction for the given velocity (> 0 means forward)
  defp set_direction_for_velocity(pid, velocity) when velocity < 0 do
    GPIO.write(pid, @motor_backward)
  end

  defp set_direction_for_velocity(pid, _velocity) do
    GPIO.write(pid, @motor_forward)
  end

  @doc """
  Sets the velocity for the controller associated with the given pid.
  Velocity must be in the range -1 to 1.
  """
  def set_velocity(direction_pid, speed_pid, velocity) do
    Logger.debug("Setting velocity to #{velocity} using speed pid #{Kernel.inspect(speed_pid)}")
    speed = abs(velocity)
    set_direction_for_velocity(direction_pid, velocity)
    set_speed(speed_pid, speed)
  end
end
