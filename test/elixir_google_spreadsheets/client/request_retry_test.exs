defmodule GSS.Client.RequestRetryTest do
  @moduledoc """
  Unit tests for the pure retry classification/backoff helpers in
  `GSS.Client.Request`. The full send -> retryable -> re-enqueue loop is covered
  by the offline HTTP suite (see spreadsheet_http_test.exs), not here.
  """
  use ExUnit.Case, async: true

  alias GSS.Client.Request

  # Jitter is `:rand.uniform(1_000)` (1..1_000). Run bound assertions across many
  # samples so a lucky/unlucky draw can never make the suite flaky.
  @samples 200

  describe "retryable?/2 — 429 (rate limited) retries for every method" do
    test "429 is retryable for write methods" do
      for method <- [:post, :put, :patch, :delete] do
        assert Request.retryable?(method, 429), "expected 429 retryable for #{method}"
      end
    end

    test "429 is retryable for :get" do
      assert Request.retryable?(:get, 429)
    end
  end

  describe "retryable?/2 — 5xx / transport errors retry for :get only" do
    test "5xx is retryable for :get" do
      for status <- [500, 502, 503, 504] do
        assert Request.retryable?(:get, status), "expected #{status} retryable for :get"
      end
    end

    test "5xx is NOT retryable for write methods" do
      for method <- [:post, :put, :patch, :delete], status <- [500, 502, 503, 504] do
        refute Request.retryable?(method, status),
               "expected #{status} not retryable for #{method}"
      end
    end

    test "transport error retries for :get only" do
      assert Request.retryable?(:get, :error)
      refute Request.retryable?(:post, :error)
      refute Request.retryable?(:put, :error)
    end
  end

  describe "retryable?/2 — non-retryable statuses" do
    test "4xx client errors are never retryable" do
      for status <- [400, 401, 403, 404, 409, 422] do
        refute Request.retryable?(:get, status), "expected #{status} not retryable for :get"
        refute Request.retryable?(:post, status), "expected #{status} not retryable for :post"
      end
    end

    test "2xx success is not retryable" do
      refute Request.retryable?(:get, 200)
      refute Request.retryable?(:post, 200)
    end
  end

  describe "retry_delay/2 — exponential backoff with jitter" do
    test "attempt 0 sits in the base 1s window plus jitter" do
      for _ <- 1..@samples do
        delay = Request.retry_delay(0)
        # base 1000ms + jitter (1..1000) => 1001..2000, within the documented 1000..3000 window
        assert delay >= 1001 and delay <= 2000, "attempt 0 delay out of bounds: #{delay}"
      end
    end

    test "delay is capped at 32s (plus jitter) for large attempts" do
      for attempt <- [5, 8, 10, 20] do
        for _ <- 1..@samples do
          delay = Request.retry_delay(attempt)

          assert delay >= 32_001 and delay <= 33_000,
                 "attempt #{attempt} delay out of cap bounds: #{delay}"
        end
      end
    end

    test "windows are strictly increasing until the cap" do
      # base(attempt) = min(2^attempt s, 32s); windows [base+1, base+1000] do not
      # overlap for attempts 0..5, so any sample of attempt n is < any of n+1.
      for attempt <- 0..4 do
        low = Request.retry_delay(attempt)
        high = Request.retry_delay(attempt + 1)
        assert low < high, "expected attempt #{attempt} (#{low}) < #{attempt + 1} (#{high})"
      end
    end
  end

  describe "retry_delay/2 — Retry-After floor" do
    test "Retry-After (ms) wins when larger than the computed delay" do
      for _ <- 1..@samples do
        assert Request.retry_delay(0, 60_000) == 60_000
      end
    end

    test "Retry-After is ignored when smaller than the computed delay" do
      for _ <- 1..@samples do
        delay = Request.retry_delay(0, 500)
        assert delay >= 1001 and delay <= 2000, "expected base window, got #{delay}"
      end
    end

    test "nil Retry-After leaves the computed delay untouched" do
      for _ <- 1..@samples do
        delay = Request.retry_delay(3, nil)
        # 2^3 s = 8000ms base + jitter => 8001..9000
        assert delay >= 8001 and delay <= 9000, "attempt 3 delay out of bounds: #{delay}"
      end
    end
  end
end
