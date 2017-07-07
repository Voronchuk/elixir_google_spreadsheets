defmodule GSS.Client.Request do
    @moduledoc """
    Worker of Request subscribed to Limiter, call request to API and send an answer to Client.
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
    Takes events from Limiter and send requests through HTTPoison

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
        Logger.debug "Request init: #{inspect args}"
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
        Logger.debug "Request handle events: #{inspect request}"

        response = send_request(request)
        Logger.info "Response #{inspect response}"
        GenStage.reply(from, response)

        {:noreply, [], state}
    end

    @spec send_request(RequestParams.t) :: {:ok, HTTPoison.Response.t} | {:error, binary()}
    defp send_request(request) do
       %RequestParams{
            method: method,
            url: url,
            body: body,
            headers: headers,
            options: options
        } = request
        Logger.debug "send_request #{url}"
        try do
            case HTTPoison.request(method, url, body, headers, options) do
                {:ok, response} ->
                    {:ok, response}
                {:error, %HTTPoison.Error{reason: reason}} ->
                    Logger.error "Request poison error #{inspect reason}: #{inspect request}"
                    {:error, reason}
            end
        rescue
            error ->
                Logger.error "Request error exception #{inspect error}: #{inspect request}"
                {:error, error}
        end
    end
end
