defmodule GSS.Client.Request do
  @moduledoc """
  Worker of Request subscribed to Limiter, call request to API and send an answer to Client.

  Only `:pool_timeout`, `:receive_timeout` and `:request_timeout` from `RequestParams.options`
  are forwarded to `Finch.request/3`; any other keys (library-level or stale) are dropped.
  """

  use GenStage
  require Logger

  alias GSS.{Client, Client.RequestParams}

  @type state :: :ok

  @type options :: [
          name: atom() | nil,
          limiters: [{atom(), keyword()} | atom()]
        ]

  @doc """
  Starts an request worker linked to the current process.
  Takes events from Limiter and send requests through Finch

  ## Options
  * `:name` - used for name registration as described in the "Name registration" section of the module documentation. Default is `#{__MODULE__}`
  * `:limiters` - list of limiters with max_demand options. For example `[{#{Client.Limiter}, max_demand: 1}]`.
  """
  @spec start_link(options()) :: GenServer.on_start()
  def start_link(args) do
    GenStage.start_link(__MODULE__, args, name: args[:name] || __MODULE__)
  end

  ## Callbacks

  def init(args) do
    Logger.debug("Request init: #{inspect(args)}")
    {:consumer, :ok, subscribe_to: args[:limiters]}
  end

  @doc ~S"""
  Set the subscription to manual to control when to ask for events
  """
  def handle_subscribe(:producer, _options, _from, state) do
    {:automatic, state}
  end

  @spec handle_events([Client.event()], GenStage.from(), state()) :: {:noreply, [], state()}
  def handle_events([{:request, from, request}], _from, state) do
    Logger.debug("Request handle events: #{inspect(request)}")

    response = send_request(request)
    Logger.debug("Response #{inspect(response)}")
    GenStage.reply(from, response)

    {:noreply, [], state}
  end

  # Only these keys are valid `Finch.request/3` options as of finch 0.23 (which
  # raises on unknown keys via `Keyword.validate!`). `options` also carries
  # library-level keys (e.g. `:result_timeout`, `:range`, `:wrap_data`) used
  # elsewhere in the pipeline, and may carry stale HTTPoison-era keys from user
  # config, so we whitelist here rather than upstream.
  @finch_request_options [:pool_timeout, :receive_timeout, :request_timeout]

  @spec send_request(RequestParams.t()) :: {:ok, Finch.Response.t()} | {:error, Exception.t()}
  defp send_request(request) do
    %RequestParams{
      method: method,
      url: url,
      body: body,
      headers: headers,
      options: options
    } = request

    Logger.debug("send_request #{url}")

    finch_request = Finch.build(method, url, headers, body)
    finch_options = Keyword.take(options || [], @finch_request_options)

    case Finch.request(finch_request, GSS.Finch, finch_options) do
      {:ok, response} ->
        {:ok, response}

      {:error, error} ->
        Logger.error("Finch request error #{inspect(error)}: #{inspect(request)}")
        {:error, error}
    end
  end
end
