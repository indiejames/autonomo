defmodule Constants do
  @moduledoc """
  Defines constants used in mnore than one module in the code
  """

  defmacro __using__(_) do
    quote do
      # Maxiumum allowable value for motor speed (12 bits all set to 1)
      @max_speed 0b111111111111
      # Unbuffered Vref with output gain = 1
      @configuration_bits 0b0111000000000000
      # Raspberry Pi3 GPIO pins for controlling motor direction
      @right_motor_direction_pin 5
      @left_motor_direction_pin 6
      # Raspberry Pi3 GPIO pins for reading velocity control inputs
      @right_motor_velocity_input_pin 19
      @left_motor_velocity_input_pin 20
      # Values for controlling motor directions
      @motor_forward 1
      @motor_backward 0

      # System clock scale
      @sys_clk_scale 1_000_000_000

      # PWM max value
      @pwm_max 2.0e-3
      # PWM min value
      @pwm_min 1.0e-3

      # Max velocity value
      @max_vel 1.0
      # Min velocity value
      @min_vel -1.0

      # Velocity threshold to reduce jitter
      @vel_threshold 0.05
    end
  end
end
