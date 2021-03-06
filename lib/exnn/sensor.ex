defmodule EXNN.Sensor do

  @moduledoc """
  _Sensor server metamodule to be used within your implementation_

  #### Modules using EXNN.Sensor are turned into Sensor servers.

  Sensor modules *MUST* implement either
  a `sense/2` function emitting a tuple containing scalar impulses
  of length compatible with the configured dimension,
  or a `sync/2` function which returns sensor.
  Both functions take (sensor, {origin, :sync}) as arguments.

  A sensor has a forward(sensor, value) function available.
  In case we want to change a sensor's state during sync, we
  can override a `before_synch(state)` function in case we
  don't overridde the sync function.

  They share the underlying genome as state, which can
  be merged with custom attributes and default values
  passign a state option to the use macro.

  A sensor receives or propagates a signal from the outside world
  and broadcasts it to the neuron of the front layer.

  ## State Attributes
  - id: primary id
  - outs: neuron of the first layer
  """

  defmacro __using__(options \\ []) do
    caller = __CALLER__.module
    quote location: :keep do
      require Logger
      use EXNN.NodeServer
      defstruct unquote(options)
        |> Keyword.get(:state, [])
        |> Dict.merge([id: nil, outs: []])

      @doc "#sense must be implemented in the sensor implementation"
      def sync(sensor, metadata) do
        sensor = before_sync(sensor)
        forward(sensor, sense(sensor, metadata))
      end

      def sense(_state, _metadata) do
        raise "NotImplementedError"
      end

      def forward(sensor, value) do
        spread_value = format_impulse(sensor, value)
        cast_out = fn(out_id) ->
          EXNN.NodeServer.forward(out_id, spread_value, [{sensor.id, value}])
        end
        sensor.outs |> Enum.each(cast_out)
        Logger.debug "[EXNN.Sensor] - fanned out #{inspect value} (#{inspect spread_value}) from #{sensor.id} to #{inspect sensor.outs}"
        sensor
      end

      def before_sync(sensor), do: sensor

      @doc "value must be an enumerable compatible with the
            dimension of the sensor"
      def format_impulse(sensor, tuple) do
        sensor_id = sensor.id
        iterator = fn(val, {list, index})->
          step = {:"#{sensor_id}_#{index}", val}
          {[step | list], index + 1}
        end
        {list, num} = tuple
        |> Tuple.to_list
        |> List.foldl({[], 1}, iterator)
        list
      end

      defimpl EXNN.Connection do
        def signal(sensor, :sync, metadata) do
          unquote(caller).sync(sensor, metadata)
        end
      end

      defoverridable [before_sync: 1, sync: 2, sense: 2]
    end
  end

end
