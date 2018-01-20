defmodule Mower.Receiver do
  use GenServer
  require Logger
  use Constants
  alias ElixirALE.SPI
  alias ElixirALE.GPIO
  require Mower

  # Weights for computing weighted average of timing values from receiver
  @weights [
    0.628285,
    0.508911,
    0.402102,
    0.30786,
    0.226183,
    0.157071,
    0.100526,
    0.0565456,
    0.0251314,
    0.00628285
  ]

  def start_link do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    Logger.info("Strarting SPI server for right side wheels")
    {:ok, right_spi_pid} = SPI.start_link("spidev0.0")

    Logger.info("Strarting SPI server for left side wheels")
    {:ok, left_spi_pid} = SPI.start_link("spidev0.1")

    Logger.info("Starting pin #{@right_motor_direction_pin} as output")
    {:ok, right_dir_pid} = GPIO.start_link(@right_motor_direction_pin, :output)

    Logger.info("Starting pin #{@left_motor_direction_pin} as output")
    {:ok, left_dir_pid} = GPIO.start_link(@left_motor_direction_pin, :output)

    Logger.info("Starting pin #{@right_motor_velocity_input_pin} as input")
    {:ok, right_vel_input_pid} = GPIO.start_link(@right_motor_velocity_input_pin, :input)
    spawn(fn -> listen_forever(right_vel_input_pid, right_dir_pid, right_spi_pid) end)

    Logger.info("Starting pin #{@left_motor_velocity_input_pin} as input")
    {:ok, left_vel_input_pid} = GPIO.start_link(@left_motor_velocity_input_pin, :input)
    spawn(fn -> listen_forever(left_vel_input_pid, left_dir_pid, left_spi_pid) end)

    {:ok, state}
  end

  @doc """
  Compute the velocity for the given PWM time
  """
  def velocity(time) do
    m = (@max_vel - @min_vel) / (@pwm_max - @pwm_min)
    b = 1.0 - m * @pwm_max
    m * time + b
  end

  # Compute the weighted average of a window of samples
  defp smooth_times([]), do: nil

  defp smooth_times(times) do
    {weighted_sum, sum_of_sq_weights} =
      Enum.zip(times, @weights)
      |> Enum.reduce({0, 0}, fn {time, weight}, {weighted_sum, sum_of_sq_weights} ->
        weighted_sum = weighted_sum + time * weight
        sum_of_sq_weights = sum_of_sq_weights + weight * weight
        {weighted_sum, sum_of_sq_weights}
      end)

    weighted_sum / :math.sqrt(sum_of_sq_weights)
  end

  defp listen_forever(input_pid, output_dir_pid, output_spd_pid) do
    # Start listening for interrupts on rising and falling edges
    GPIO.set_int(input_pid, :both)
    listen_loop(output_dir_pid, output_spd_pid, 0, [])
  end

  # Set the velocity for a received PWM pulse
  defp set_velocity(output_dir_pid, output_spd_pid, pulse_width, recv_times) do
    # Guard against pulses that are too long - these could be the result of having missed 
    # a rising or trailing edge
    if pulse_width < 2 * @pwm_max do
      # Force time into @pwm_min..@pwm_max range
      pulse_width = min(pulse_width, @pwm_max) |> max(@pwm_min)

      recv_times = Enum.concat([pulse_width], recv_times) |> Enum.take(Enum.count(@weights))
      smoothed_time = smooth_times(recv_times)
      vel = velocity(smoothed_time)
      Mower.set_velocity(output_dir_pid, output_spd_pid, vel)
      recv_times
    else
      recv_times
    end
  end

  defp listen_loop(output_dir_pid, output_spd_pid, rising_edge_timestamp, recv_times) do
    # Infinite loop receiving interrupts from gpio
    receive do
      {:gpio_interrupt, _p, :rising} ->
        listen_loop(output_dir_pid, output_spd_pid, System.system_time(), recv_times)

      {:gpio_interrupt, _p, :falling} ->
        # elapsed time since falling rising edge
        time = (System.system_time() - rising_edge_timestamp) / @sys_clk_scale
        recv_times = set_velocity(output_dir_pid, output_spd_pid, time, recv_times)
        listen_loop(output_dir_pid, output_spd_pid, 0, recv_times)
    end
  end
end
