defmodule Zexbox.Metrics.MetricHandler do
  @moduledoc """
  This module is responsible for logging controller metrics to influx
  """
  alias Zexbox.Metrics.{Client, ControllerSeries}
  require Logger

  @doc """
  This function is called by the Phoenix endpoint when a controller action is
  finished. It will log the controller metrics to influx.

  ## Examples

      iex> Zexbox.Metrics.MetricHandler.handle_event([:phoenix, :endpoint, :stop], measurements, metadata, config)
      :ok

  """
  @spec handle_event(list(atom()), map(), map(), map()) :: any()
  def handle_event([:phoenix, :endpoint, :stop], measurements, metadata, config) do
    case required_fields_present?(metadata) do
      true ->
        measurements
        |> create_controller_series(metadata)
        |> write_metric(config)

      false ->
        Logger.debug("Required fields not present in metadata")
        nil
    end
  rescue
    exception ->
      Logger.debug("Exception creating controller series: #{inspect(exception)}")
  end

  defp required_fields_present?(%{conn: %{private: private}}) do
    action = private[:phoenix_action]
    format = private[:phoenix_format]
    controller = private[:phoenix_controller]

    !(is_nil(action) || is_nil(format) || is_nil(controller))
  end

  defp required_fields_present?(_metadata) do
    false
  end

  defp create_controller_series(measurements, metadata) do
    status = metadata.conn.status

    %ControllerSeries{}
    |> ControllerSeries.tag(:method, metadata.conn.method)
    |> ControllerSeries.tag(:status, status)
    |> ControllerSeries.tag(:action, Atom.to_string(metadata.conn.private.phoenix_action))
    |> ControllerSeries.tag(:format, metadata.conn.private.phoenix_format)
    |> ControllerSeries.tag(:controller, Atom.to_string(metadata.conn.private.phoenix_controller))
    |> ControllerSeries.field(:count, 1)
    |> ControllerSeries.field(:success, success?(status))
    |> ControllerSeries.field(:path, metadata.conn.request_path)
    |> ControllerSeries.field(:duration_ms, duration(measurements))
    |> set_referer_field(metadata)
    |> set_trace_id_field(metadata)
  end

  defp set_trace_id_field(series, metadata) do
    case metadata.conn[:assigns][:trace_id] do
      nil ->
        series

      trace_id ->
        ControllerSeries.field(series, :trace_id, trace_id)
    end
  end

  defp set_referer_field(series, metadata) do
    case Enum.find(metadata.conn.req_headers, fn {key, _value} -> key == "referer" end) do
      nil ->
        series

      {_key, value} ->
        ControllerSeries.field(series, :http_referer, value)
    end
  end

  defp duration(measurements) do
    System.convert_time_unit(measurements.duration, :native, :millisecond)
  end

  defp success?(status) do
    case status do
      status when status in 200..399 -> 1.0
      _status -> 0.0
    end
  end

  defp write_metric(metric, %{metric_client: client}) do
    client.write_metric(metric)
  end

  defp write_metric(metric, _config) do
    Client.write_metric(metric)
  end
end
