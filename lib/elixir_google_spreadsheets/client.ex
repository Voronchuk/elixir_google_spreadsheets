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
            body: binary() | iodata(),
            headers: [{binary(), binary()}],
            options: Keyword.t()
          }
    defstruct method: nil, url: nil, body: "", headers: [], options: []
  end

  @type event :: {:request, GenStage.from(), RequestParams.t()}
  @type partition :: :write | :read

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_args \\ []) do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Issues an HTTP request with the given method to the given URL using Finch.

  This function is usually used indirectly by helper functions such as `get/3`, `post/4`, `put/4`, etc.

  ### Arguments
  - **`method`**: HTTP method as an atom (e.g., `:get`, `:head`, `:post`, `:put`, `:delete`, etc.).
  - **`url`**: Target URL as a binary string.
  - **`body`**: Request body, which can be a binary, char list, or iodata. Special forms include:
    - `{:form, [{K, V}, ...]}` – to send a form URL-encoded payload.
    - `{:file, "/path/to/file"}` – to send a file.
    - `{:stream, enumerable}` – to lazily send a stream of binaries/char lists.
  - **`headers`**: HTTP headers as a list of two-element tuples (e.g., `[{"Accept", "application/json"}]`).
  - **`options`**: A keyword list of Finch options. Supported options include:
    - **`:timeout`** – Timeout (in milliseconds) for establishing a connection (default is 8000).
    - **`:recv_timeout`** – Timeout (in milliseconds) for receiving data (default is 5000).
    - **`:proxy`** – A proxy for the request; either a URL or a `{host, port}` tuple.
    - **`:proxy_auth`** – Proxy authentication credentials as `{user, password}`.
    - **`:ssl`** – SSL options as supported by Erlang’s `ssl` module.
    - **`:follow_redirect`** – Boolean to indicate if redirects should be followed.
    - **`:max_redirect`** – Maximum number of redirects to follow.
    - **`:params`** – Enumerable of two-item tuples to be appended to the URL as query string parameters.
    - Any other Finch-supported options can also be provided.

  Timeout values can be specified as an integer or as `:infinity`.

  ### Returns
  - On success, returns `{:ok, %Finch.Response{}}`.
  - On failure, returns `{:error, reason}` where `reason` is an exception.

  ### Examples

      request(:post, "https://my.website.com", "{\"foo\": 3}", [{"Accept", "application/json"}])
  """
  @spec request(atom, binary, binary() | iodata(), [{binary(), binary()}], Keyword.t()) ::
    {:ok, Finch.Response.t()} | {:error, Exception.t()}
  def request(method, url, body \\ "", headers \\ [], options \\ []) do
    request = %RequestParams{
      method: method,
      url: safe_encode_url(url),
      body: body,
      headers: maybe_parse_headers(headers),
      options: options
    }

    case options[:result_timeout] || config(:result_timeout) do
      nil ->
        GenStage.call(__MODULE__, {:request, request})

      recv_timeout ->
        GenStage.call(__MODULE__, {:request, request}, recv_timeout)
    end
  end

  @doc """
  Starts a task with request that must be awaited on.
  """
  @spec request_async(atom, binary, binary() | iodata(), [{binary(), binary()}], Keyword.t()) ::
          Task.t()
  def request_async(method, url, body \\ "", headers \\ [], options \\ []) do
    Task.async(GSS.Client, :request, [method, url, body, headers, options])
  end

  ## Callbacks

  def init(:ok) do
    dispatcer =
      {GenStage.PartitionDispatcher, partitions: [:write, :read], hash: &dispatcher_hash/1}

    {:producer, :queue.new(), dispatcher: dispatcer}
  end

  @doc """
  Divide request into to partitions :read and :write
  """
  @spec dispatcher_hash(event) :: {event, partition()}
  def dispatcher_hash({:request, _from, request} = event) do
    case request.method do
      :get -> {event, :read}
      _ -> {event, :write}
    end
  end

  @doc """
  Adds an event to the queue
  """
  def handle_call({:request, request}, from, queue) do
    updated_queue = :queue.in({:request, from, request}, queue)
    {:noreply, [], updated_queue}
  end

  @doc """
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

  defp safe_encode_url(url) do
    # Replace spaces with %20 while leaving colons and other reserved characters intact.
    String.replace(url, " ", "%20")
  end

  defp maybe_parse_headers(headers) when is_list(headers), do: headers
  defp maybe_parse_headers(%{} = headers) do
    Enum.reduce(headers, [], fn {k, v}, acc -> [{k, v} | acc] end)
  end
end
