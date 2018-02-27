defmodule GSS.Client do
    @moduledoc """
    Model of Client abstraction
    This process is a Producer for this GenStage pipeline.
    """

    use GenStage
    require Logger

    defmodule RequestParams do
        @type t :: %__MODULE__{
            method: atom(),
            url: binary(),
            body: HTTPoison.body(),
            headers: HTTPoison.headers(),
            options: Keyword.t()
        }
        defstruct [method: nil, url: nil, body: "", headers: [], options: []]
    end

    @type event :: {:request, GenStage.from(), RequestParams.t}
    @type partition :: :write | :read

    @spec start_link() :: GenServer.on_start()
    def start_link do
        GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
    end

    @doc ~S"""
    Issues an HTTP request with the given method to the given url.

    This function is usually used indirectly by `get/3`, `post/4`, `put/4`, etc

    Args:
    * `method` - HTTP method as an atom (`:get`, `:head`, `:post`, `:put`,
      `:delete`, etc.)
    * `url` - target url as a binary string or char list
    * `body` - request body. See more below
    * `headers` - HTTP headers as an orddict (e.g., `[{"Accept", "application/json"}]`)
    * `options` - Keyword list of options

    Body:
    * binary, char list or an iolist
    * `{:form, [{K, V}, ...]}` - send a form url encoded
    * `{:file, ~s(/path/to/file)}` - send a file
    * `{:stream, enumerable}` - lazily send a stream of binaries/charlists

    Options:
    * `:result_timeout` - receive result timeout, in milliseconds. Default is 2 minutes
    * `:timeout` - timeout to establish a connection, in milliseconds. Default is 8000
    * `:recv_timeout` - timeout used when receiving a connection. Default is 5000
    * `:proxy` - a proxy to be used for the request; it can be a regular url
      or a `{Host, Port}` tuple
    * `:proxy_auth` - proxy authentication `{User, Password}` tuple
    * `:ssl` - SSL options supported by the `ssl` erlang module
    * `:follow_redirect` - a boolean that causes redirects to be followed
    * `:max_redirect` - an integer denoting the maximum number of redirects to follow
    * `:params` - an enumerable consisting of two-item tuples that will be appended to the url as query string parameters

    Timeouts can be an integer or `:infinity`

    This function returns `{:ok, response}` or `{:ok, async_response}` if the
    request is successful, `{:error, reason}` otherwise.

    ## Examples

      request(:post, ~s(https://my.website.com), ~s({\"foo\": 3}), [{"Accept", "application/json"}])

    """
    @spec request(atom, binary, HTTPoison.body, HTTPoison.headers, Keyword.t) :: {:ok, HTTPoison.Response.t} | {:error, binary} | no_return
    def request(method, url, body \\ "", headers \\ [], options \\ []) do
        result_timeout = options[:result_timeout] || config(:result_timeout)
        request = %RequestParams{
          method: method,
          url: url,
          body: body,
          headers: headers,
          options: options
        }
        GenStage.call(__MODULE__, {:request, request}, result_timeout)
    end

    @doc ~S"""
    Starts a task with request that must be awaited on.
    """
    @spec request_async(atom, binary, HTTPoison.body, HTTPoison.headers, Keyword.t) :: Task.t
    def request_async(method, url, body \\ "", headers \\ [], options \\ []) do
        Task.async(GSS.Client, :request, [method, url, body, headers, options])
    end

    ## Callbacks

    def init(:ok) do
        dispatcer = {GenStage.PartitionDispatcher, partitions: [:write, :read], hash: &dispatcher_hash/1}
        {:producer, :queue.new(), dispatcher: dispatcer}
    end

    @doc ~S"""
    Divide request into to partitions :read and :write
    """
    @spec dispatcher_hash(event) :: {event, partition()}
    def dispatcher_hash({:request, _from, request} = event) do
        case request.method do
            :get -> {event, :read}
            _ -> {event, :write}
        end
    end

    @doc ~S"""
    Adds an event to the queue
    """
    def handle_call({:request, request}, from, queue) do
        updated_queue  = :queue.in({:request, from, request}, queue)
        {:noreply, [], updated_queue}
    end

    @doc ~S"""
    Gives events for the next stage to process when requested
    """
    def handle_demand(demand, queue) when demand > 0 do
        {events, updated_queue} = take_from_queue(queue, demand, [])
        {:noreply, Enum.reverse(events), updated_queue}
    end

    
    @doc """
    Read config settings scoped for GSS client.
    """
    @spec config(atom(), any()) :: any()
    def config(key, default \\ nil) do
      Application.get_env(:elixir_google_spreadsheets, :client)
      |> Keyword.get(key, default)
    end

    # take demand events from the queue
    defp take_from_queue(queue, 0, events) do
        {events, queue}
    end
    defp take_from_queue(queue, demand, events) do
        case :queue.out(queue) do
            {{:value, {kind, from, event}}, queue} ->
                take_from_queue(queue, demand - 1, [{kind, from, event} | events])
            {:empty, queue} ->
                take_from_queue(queue, 0, events)
        end
    end
end
