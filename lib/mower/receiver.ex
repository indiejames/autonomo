defmodule Mower.Receiver do
  use GenServer
  require Logger
  use Constants
  alias ElixirALE.SPI
  alias ElixirALE.GPIO
  require Pigpiox.GPIO
  require Mower

  #@compile if Mix.env == :test, do: :export_all

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

  # @weights [
  #   1.0
  # ]

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(state) do
    Logger.debug("Initializing receiver")
    # TODO add state that will help in debugging
    Logger.debug("Starting GPIO services")
    Logger.debug("Strarting SPI server for right side wheels")
    {:ok, right_spi_pid} = SPI.start_link("spidev0.1")

    Logger.debug("Strarting SPI server for left side wheels")
    {:ok, left_spi_pid} = SPI.start_link("spidev0.0")

    Logger.debug("Starting pin #{@right_motor_direction_pin} as output")
    {:ok, right_dir_pid} = GPIO.start_link(@right_motor_direction_pin, :output)

    Logger.debug("Starting pin #{@left_motor_direction_pin} as output")
    {:ok, left_dir_pid} = GPIO.start_link(@left_motor_direction_pin, :output)

    Logger.debug("Starting pin #{@right_motor_velocity_input_pin} as input")
    # {:ok, right_vel_input_pid} = GPIO.start_link(@right_motor_velocity_input_pin, :input)
    # spawn(fn -> listen_forever(right_vel_input_pid, right_dir_pid, right_spi_pid) end)
    Pigpiox.GPIO.set_mode(@right_motor_velocity_input_pin, :input)
    spawn(fn -> listen_forever(@right_motor_velocity_input_pin, right_dir_pid, right_spi_pid) end)

    Logger.debug("Starting pin #{@left_motor_velocity_input_pin} as input")
    # {:ok, left_vel_input_pid} = GPIO.start_link(@left_motor_velocity_input_pin, :input)
    # spawn(fn -> listen_forever(left_vel_input_pid, left_dir_pid, left_spi_pid) end)
    Pigpiox.GPIO.set_mode(@left_motor_velocity_input_pin, :input)
    spawn(fn -> listen_forever(@left_motor_velocity_input_pin, left_dir_pid, left_spi_pid) end)

    {:ok, state}
  end

  # Allow me to look up the state of this server so I can do some debugging
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # Compute the velocity for the given PWM pulse width
  defp velocity(pulse_width) do
    vel = (pulse_width - @pwm_center) / @pwm_half_width
    
    # ignore really small velocities to reduce jitter
    if abs(vel) < @vel_threshold, do: 0.0, else: vel

  end

  # Compute the weighted average of a window of samples
  defp smooth_times([]), do: nil

  defp smooth_times(times) do
    {weighted_sum, sum_of_weights} =
      Enum.zip(times, @weights)
      |> Enum.reduce({0, 0}, fn {time, weight}, {weighted_sum, sum_of_weights} ->
        weighted_sum = weighted_sum + time * weight
        sum_of_weights = sum_of_weights + weight
        {weighted_sum, sum_of_weights}
      end)
    weighted_sum / sum_of_weights
  end

  # defp listen_forever(input_pid, output_dir_pid, output_spd_pid) do
  defp listen_forever(input_pin, output_dir_pid, output_spd_pid) do
    # Start listening for interrupts on rising and falling edges
    Pigpiox.GPIO.watch(input_pin)
    #GPIO.set_int(input_pid, :both)
    # Start with 0 velocity
    # Mower.set_velocity(output_dir_pid, output_spd_pid, 0)
    listen_loop(output_dir_pid, output_spd_pid, 0, [], 0)
  end

  # Set the velocity for a received PWM pulse
  defp set_velocity(output_dir_pid, output_spd_pid, pulse_width, recv_times) do

    # Guard against pulses that are too long - these could be the result of having missed 
    # a rising or trailing edge. Also guard against phantom pulses that are too short.
    if pulse_width <= @pwm_max && pulse_width >= @pwm_min do
  
      recv_times = Enum.concat([pulse_width], recv_times) |> Enum.take(Enum.count(@weights))
      smoothed_time = smooth_times(recv_times)
      vel = velocity(smoothed_time)
      Mower.set_velocity(output_dir_pid, output_spd_pid, vel)
      recv_times
    else
      recv_times
    end
  end

  defp listen_loop(output_dir_pid, output_spd_pid, rising_edge_timestamp, recv_times, count) do
    # Infinite loop receiving interrupts from gpio
    receive do
      {:gpio_leveL_change, p, level} ->
        t = System.monotonic_time()
        if level == 1 do 
          Logger.info("Pin #{p} rising...")
          listen_loop(output_dir_pid, output_spd_pid, t, recv_times, count)
        else
          pulse_width = (t - rising_edge_timestamp) |>
                        System.convert_time_unit(:native, :micro_seconds)
          pulse_width = pulse_width / 1.0e3
          # count = if count >= 20 do
          Logger.info("Pin #{p} falling...")
          Logger.info("Pin #{p} pulse width = #{pulse_width} ms")
            # 0
          # else
            # count + 1
          # end
          # recv_times = set_velocity(output_dir_pid, output_spd_pid, pulse_width, recv_times)
          listen_loop(output_dir_pid, output_spd_pid, 0, recv_times, count)
        end
        # if count == 20 do
        # Logger.info("#{action} edge detected on pin #{p}")
        # end
        

      # {:gpio_level_change, p, level} ->
      #   Logger.info("Falling edge detected on pin #{p} with level #{level}")
      #   pulse_width = (System.monotonic_time() - rising_edge_timestamp) |>
      #                 System.convert_time_unit(:native, :micro_seconds)
      #   pulse_width = pulse_width / 1.0e6
      #   # count = 
      #   #   if count == 20 do
      #   Logger.info("Falling edge detected on pin #{p}")
      #   Logger.info("Pulse width = #{pulse_width}")
      #     #   0
      #     # else
      #     #   count + 1
      #     # end
        
      #   recv_times = set_velocity(output_dir_pid, output_spd_pid, pulse_width, recv_times)
      #   listen_loop(output_dir_pid, output_spd_pid, 0, recv_times, count)

      # {:gpio_interrupt, _p, :rising} ->
      #   listen_loop(output_dir_pid, output_spd_pid, System.monotonic_time(), recv_times)

      # {:gpio_interrupt, _p, :falling} ->
      #   # elapsed time since rising edge
      #   pulse_width = (System.monotonic_time() - rising_edge_timestamp) |>
      #                  System.convert_time_unit(:native, :micro_seconds)
      #   pulse_width = pulse_width / 1.0e6
      #   recv_times = set_velocity(output_dir_pid, output_spd_pid, pulse_width, recv_times)
      #   listen_loop(output_dir_pid, output_spd_pid, 0, recv_times)
    end
  end
end
