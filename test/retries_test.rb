# frozen_string_literal: true

require_relative "test_helper"

class RetriesTest < UrlpipeTest
  URL = "https://example.com"

  def test_503_then_200_succeeds_with_the_same_idempotency_key
    @server.respond(503, "busy").respond(200, "# Hi")

    response = client.markdown(URL)

    assert_equal "# Hi", response.data
    keys = @server.requests.map { |request| request["Idempotency-Key"] }
    assert_equal 2, keys.size
    assert_equal keys[0], keys[1]
  end

  def test_a_given_idempotency_key_is_reused_on_retry
    @server.respond(502, "bad gateway").respond(200, "ok")

    client.markdown(URL, idempotency_key: "job-42")

    assert_equal %w[job-42 job-42], @server.requests.map { |request| request["Idempotency-Key"] }
  end

  def test_gives_up_after_max_retries
    @server.respond(500, "a").respond(500, "b")

    error = assert_raises(Urlpipe::ServerError) { client(max_retries: 1).markdown(URL) }

    assert_equal "HTTP 500: b", error.message
    assert_equal 2, @server.requests.size
  end

  def test_422_is_not_retried
    @server.respond(422, { "error" => "invalid_url" }).respond(200, "ok")

    assert_raises(Urlpipe::InvalidRequestError) { client.markdown(URL) }
    assert_equal 1, @server.requests.size
  end

  def test_quota_exceeded_is_not_retried
    @server.respond(429, { "error" => "quota_exceeded" }).respond(200, "ok")

    assert_raises(Urlpipe::QuotaExceededError) { client.markdown(URL) }
    assert_equal 1, @server.requests.size
  end

  def test_rate_limited_honours_retry_after
    @server.respond(429, { "error" => "rate_limited", "retry_after" => 0 }, "Retry-After" => "0")
           .respond(200, "ok")

    assert_equal "ok", client.markdown(URL).data
    assert_equal 2, @server.requests.size
  end

  def test_unknown_429_is_not_retried
    @server.respond(429, { "error" => "mystery" }).respond(200, "ok")

    error = assert_raises(Urlpipe::Error) { client.markdown(URL) }
    assert_equal 429, error.status
    assert_equal 1, @server.requests.size
  end

  def test_rate_limited_without_retry_after_waits_one_second
    @server.respond(429, { "error" => "rate_limited" }).respond(200, "ok")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_equal "ok", client.markdown(URL).data

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_operator elapsed, :>=, 1.0
    assert_operator elapsed, :<, 1.9
  end

  def test_result_504_other_than_processing_timeout_is_a_server_error_and_not_retried
    @server.respond(504, "gateway timeout").respond(200, "ok")

    assert_raises(Urlpipe::ServerError) { client.result("tok") }
    assert_equal 1, @server.requests.size
  end

  def test_result_polling_sends_no_idempotency_key
    @server.respond(503, "busy").respond(200, "ok")

    client.result("tok")

    assert_equal [false, false], @server.requests.map { |request| request.headers.key?("idempotency-key") }
  end

  def test_concurrency_limit_is_retried_with_backoff
    @server.respond(429, { "error" => "concurrency_limit", "limit" => 1, "running" => 1 }).respond(200, "ok")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_equal "ok", client.markdown(URL).data

    assert_equal 2, @server.requests.size
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :>=, 1.0
  end

  def test_dropped_connection_is_retried_with_the_same_key
    @server.drop.respond(200, "ok")

    assert_equal "ok", client.markdown(URL).data
    keys = @server.requests.map { |request| request["Idempotency-Key"] }
    assert_equal 2, keys.size
    assert_equal keys[0], keys[1]
  end

  def test_result_polling_retries_server_errors
    @server.respond(503, "busy").respond(200, "# Hi")

    assert_equal "# Hi", client.result("tok", operation: "markdown").data
  end
end
