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

  @impl true
  def init(args) do
    Logger.debug("Request init: #{inspect(args)}")
    {:consumer, :ok, subscribe_to: args[:limiters]}
  end

  @impl true
  # Set the subscription to manual to control when to ask for events
  def handle_subscribe(:producer, _options, _from, state) do
    {:automatic, state}
  end

  # HTTP statuses that are safe to retry regardless of method: the request was
  # rejected by rate limiting, not executed server-side.
  @retryable_any_status [429]

  # HTTP statuses retried for idempotent (:get) requests only. A 5xx on a write
  # may have been applied server-side, so retrying it risks a duplicate mutation.
  @retryable_get_status [429, 500, 502, 503, 504]

  # Default number of retries when the `:client` config key is absent.
  @default_max_retries 3

  @impl true
  @spec handle_events([Client.event()], GenStage.from(), state()) :: {:noreply, [], state()}
  def handle_events([{:request, from, request}], _from, state) do
    Logger.debug("Request handle events: #{inspect(request)}")

    response = send_request(request)
    Logger.debug("Response #{inspect(response)}")

    unless maybe_schedule_retry(request, response, from) do
      GenStage.reply(from, response)
    end

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

  # Classify the response and, when it is retryable and retries remain, schedule
  # the request to re-enter the pipeline (via `GSS.Client`). Returns `true` when
  # a retry was scheduled (caller must NOT reply yet), `false` otherwise.
  @spec maybe_schedule_retry(RequestParams.t(), Client.response(), GenStage.from()) :: boolean()
  defp maybe_schedule_retry(
         %RequestParams{method: method, attempt: attempt} = request,
         response,
         from
       ) do
    outcome = classify_response(response)
    max_retries = Client.config(:max_retries, @default_max_retries)

    if retryable?(method, outcome) and attempt < max_retries do
      delay = retry_delay(attempt, retry_after_ms(response))

      Logger.warning(
        "Retrying #{method} request (outcome=#{inspect(outcome)}, attempt=#{attempt + 1}/#{max_retries}, delay=#{delay}ms): #{request.url}"
      )

      retried = %{request | attempt: attempt + 1}
      Process.send_after(Client, {:retry, {:request, from, retried}}, delay)
      true
    else
      false
    end
  end

  # Reduce a Finch result to the value used for retry classification: the HTTP
  # status integer on a completed response, or `:error` on a transport error.
  @spec classify_response(Client.response()) :: non_neg_integer() | :error
  defp classify_response({:ok, %Finch.Response{status: status}}), do: status
  defp classify_response({:error, _reason}), do: :error

  @doc false
  # Whether an outcome (HTTP status or `:error` transport failure) is retryable
  # for the given method. 429 retries for every method; 5xx and transport errors
  # retry for idempotent `:get` requests only (writes are not idempotent).
  @spec retryable?(atom(), non_neg_integer() | :error) :: boolean()
  def retryable?(:get, outcome) when outcome in @retryable_get_status, do: true
  def retryable?(:get, :error), do: true
  def retryable?(_method, outcome) when outcome in @retryable_any_status, do: true
  def retryable?(_method, _outcome), do: false

  @doc false
  # Exponential backoff with full jitter, capped at 32s:
  # `min(2^attempt s, 32s) + rand(1..1000) ms`. A `retry-after` value (in ms)
  # acts as a floor when it is larger than the computed delay.
  @spec retry_delay(non_neg_integer(), non_neg_integer() | nil) :: pos_integer()
  def retry_delay(attempt, retry_after_ms \\ nil) do
    delay = min(:timer.seconds(2 ** attempt), 32_000) + :rand.uniform(1_000)

    case retry_after_ms do
      ms when is_integer(ms) -> max(ms, delay)
      nil -> delay
    end
  end

  # Extract the `retry-after` header (integer seconds only) as milliseconds.
  # HTTP-date form or a missing header yields `nil`.
  @spec retry_after_ms(Client.response()) :: non_neg_integer() | nil
  defp retry_after_ms({:ok, %Finch.Response{headers: headers}}) do
    with {_key, value} <- List.keyfind(headers, "retry-after", 0),
         {seconds, ""} <- Integer.parse(value) do
      :timer.seconds(seconds)
    else
      _ -> nil
    end
  end

  defp retry_after_ms(_response), do: nil
end
