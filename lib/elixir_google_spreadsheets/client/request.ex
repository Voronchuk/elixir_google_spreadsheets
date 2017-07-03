defmodule GSS.Client.Request do
    use GenStage
    require Logger

    @doc """
    Starts an request worker linked to the current process.
    Takes events from Limiter and send requests through HTTPoison

    ## Options
    * `:limiters` - list of limiters with max_demand options. For example `[{GSS.Client.Limiter, max_demand: 1}]`.
    """
    def start_link(args) do
        GenStage.start_link(__MODULE__, args)
    end

    ## Callbacks
    def init(args) do
        Logger.debug "Request init: #{inspect args}"
        {:consumer, :ok, subscribe_to: args[:limiters]}
    end

    # Set the subscription to manual to control when to ask for events
    def handle_subscribe(:producer, _options, _from, state) do
        {:automatic, state}
    end

    def handle_events([{:request, from, request}], _from, state) do
        Logger.debug "Request handle events: #{inspect request}"

        response = send_request(request)
        Logger.info "Response #{inspect response}"
        GenStage.reply(from, response)

        {:noreply, [], state}
    end

    defp send_request(request) do
       %GSS.Client.RequestParams{
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
                    {:error, reason}
                error ->
                    {:error, error}
            end
        rescue
            error -> {:error, error}
        end
    end
end
