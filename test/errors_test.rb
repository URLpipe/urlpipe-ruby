# frozen_string_literal: true

require_relative "test_helper"

class ErrorsTest < UrlpipeTest
  URL = "https://example.com"

  def raise_from(status, body, headers = {}, &call)
    @server.respond(status, body, headers)
    call ||= -> { client(max_retries: 0).markdown(URL) }
    assert_raises(Urlpipe::Error, &call)
  end

  def test_401_is_an_authentication_error
    error = raise_from(401, "")

    assert_instance_of Urlpipe::AuthenticationError, error
    assert_equal 401, error.status
    assert_match(/API key/, error.message)
  end

  def test_401_with_a_json_body_keeps_it
    error = raise_from(401, { "error" => "unauthorized" })

    assert_instance_of Urlpipe::AuthenticationError, error
    assert_equal "unauthorized", error.code
    assert_equal({ "error" => "unauthorized" }, error.body)
  end

  def test_403_email_unverified
    error = raise_from(403, { "error" => "email_unverified",
                              "message" => "Confirm the email address on this account before using the API." })

    assert_instance_of Urlpipe::EmailUnverifiedError, error
    assert_equal 403, error.status
    assert_equal "email_unverified", error.code
    assert_equal "Confirm the email address on this account before using the API.", error.message
  end

  def test_403_email_unverified_without_a_message_still_says_to_confirm_the_email
    error = raise_from(403, { "error" => "email_unverified" })

    assert_instance_of Urlpipe::EmailUnverifiedError, error
    assert_equal "email_unverified", error.code
    assert_equal Urlpipe::ErrorFactory::DEFAULT_MESSAGES[Urlpipe::EmailUnverifiedError], error.message
  end

  def test_a_bare_code_without_a_default_gets_a_sentence
    error = raise_from(422, { "error" => "invalid_url" })

    assert_instance_of Urlpipe::InvalidRequestError, error
    assert_equal "The API refused the request with HTTP 422 (invalid_url).", error.message
  end

  def test_403_with_an_empty_body_uses_the_default_sentence
    error = raise_from(403, "")

    assert_instance_of Urlpipe::Error, error
    assert_equal "HTTP 403", error.message
  end

  def test_other_403_is_the_base_error
    error = raise_from(403, { "error" => "forbidden", "message" => "Nope." })

    assert_instance_of Urlpipe::Error, error
    assert_equal "forbidden", error.code
    assert_equal "Nope.", error.message
  end

  def test_404_and_410_whatever_the_body
    assert_instance_of Urlpipe::NotFoundError, raise_from(404, "<html>Not here</html>") { client.result("x") }
    error = raise_from(410, "") { client.result("x") }
    assert_instance_of Urlpipe::StaleResultError, error
    assert_equal "This result is older than the 30-day retention window. Run a new analysis.", error.message
  end

  def test_422_parameter_codes_are_invalid_request_errors
    %w[invalid_url invalid_max_age invalid_options invalid_labels invalid_idempotency_key
       idempotency_key_reused].each do |code|
      error = raise_from(422, { "error" => code, "message" => "Explains #{code}." })

      assert_instance_of Urlpipe::InvalidRequestError, error, code
      assert_equal 422, error.status
      assert_equal code, error.code
      assert_equal "Explains #{code}.", error.message
    end
  end

  def test_422_report_to_is_an_invalid_request_error
    error = raise_from(422, { "error" => "report_to must not be an IP address." })

    assert_instance_of Urlpipe::InvalidRequestError, error
    assert_equal "report_to must not be an IP address.", error.message
    assert_nil error.code
  end

  def test_422_sentence_is_an_analysis_failure
    error = raise_from(422, { "error" => "The requested page was not found." })

    assert_instance_of Urlpipe::AnalysisFailedError, error
    assert_equal "The requested page was not found.", error.message
    assert_nil error.code
    assert_equal({ "error" => "The requested page was not found." }, error.body)
  end

  def test_422_scrape_where_every_operation_failed_keeps_the_scrape_body
    body = { "url" => URL, "operations" => {
      "markdown" => { "success" => false, "result" => nil, "error" => "The page could not be loaded.", "cached" => false },
      "meta" => { "success" => false, "result" => nil, "error" => "The page could not be loaded.", "cached" => false }
    } }

    error = raise_from(422, body) { client(max_retries: 0).scrape(URL, %w[markdown meta]) }

    assert_instance_of Urlpipe::AnalysisFailedError, error
    assert_equal body, error.body
    assert_equal "Every operation failed: markdown: The page could not be loaded.; " \
                 "meta: The page could not be loaded.", error.message
  end

  def test_429_quota_exceeded
    error = raise_from(429, { "error" => "quota_exceeded", "message" => "Your Free plan includes 1000 credits.",
                              "limit" => 1000, "used" => 990, "needed" => 17,
                              "resets_at" => "2026-10-01T00:00:00Z" })

    assert_instance_of Urlpipe::QuotaExceededError, error
    assert_equal 429, error.status
    assert_equal "quota_exceeded", error.code
    assert_equal "Your Free plan includes 1000 credits.", error.message
    assert_equal [1000, 990, 17, "2026-10-01T00:00:00Z"], [error.limit, error.used, error.needed, error.resets_at]
  end

  def test_429_concurrency_limit
    error = raise_from(429, { "error" => "concurrency_limit", "message" => "3 are already running.",
                              "limit" => 3, "running" => 3 })

    assert_instance_of Urlpipe::ConcurrencyLimitError, error
    assert_equal [3, 3], [error.limit, error.running]
  end

  def test_429_rate_limited_reads_retry_after_from_the_header
    error = raise_from(429, { "error" => "rate_limited", "message" => "Slow down.", "retry_after" => 99 },
                       "Retry-After" => "12")

    assert_instance_of Urlpipe::RateLimitedError, error
    assert_equal 12, error.retry_after
  end

  def test_429_rate_limited_falls_back_to_the_body
    error = raise_from(429, { "error" => "rate_limited", "retry_after" => 7 })

    assert_equal 7, error.retry_after
  end

  def test_404_not_found
    error = raise_from(404, { "error" => "not_found" }) { client.result("nope") }

    assert_instance_of Urlpipe::NotFoundError, error
    assert_equal "not_found", error.code
  end

  def test_410_stale
    error = raise_from(410, { "error" => "stale", "message" => "This result is older than the 30-day window." }) do
      client.result("old")
    end

    assert_instance_of Urlpipe::StaleResultError, error
    assert_equal "stale", error.code
    assert_equal "This result is older than the 30-day window.", error.message
  end

  def test_5xx_is_a_server_error
    [500, 502, 503].each do |status|
      error = raise_from(status, "<html>Bad gateway</html>")

      assert_instance_of Urlpipe::ServerError, error
      assert_equal status, error.status
      assert_equal "<html>Bad gateway</html>", error.body
    end
  end

  def test_504_without_processing_timeout_is_a_server_error
    error = raise_from(504, "upstream timed out")

    assert_instance_of Urlpipe::ServerError, error
    assert_equal "HTTP 504: upstream timed out", error.message
  end

  def test_a_broken_json_error_body_does_not_mask_the_error
    @server.respond(429, '{"error": "quota_exc', "Content-Type" => "application/json")

    error = assert_raises(Urlpipe::Error) { client(max_retries: 0).markdown(URL) }

    assert_equal 429, error.status
    assert_equal '{"error": "quota_exc', error.body
  end

  def test_the_token_falls_back_to_the_result_token_header
    error = raise_from(422, { "error" => "The request timed out." }, "X-Result-Token" => "tok_header")

    assert_equal "tok_header", error.token
  end

  def test_unknown_429_is_the_base_error
    error = raise_from(429, { "error" => "something_else" })

    assert_instance_of Urlpipe::Error, error
    assert_equal "something_else", error.code
  end

  def test_the_body_token_is_kept
    error = raise_from(422, { "error" => "The request timed out.", "token" => "tok_failed" })

    assert_equal "tok_failed", error.token
  end
end
