# frozen_string_literal: true

require_relative "test_helper"

class AsyncTest < UrlpipeTest
  URL = "https://example.com"
  ACCEPTED = { "token" => "tok_async", "status" => "accepted", "labels" => { "client" => "acme" } }.freeze
  PROCESSING = { "status" => "processing", "token" => "tok_async", "labels" => {} }.freeze
  TIMEOUT_BODY = {
    "error" => "processing_timeout",
    "message" => "The analysis is taking longer than expected.",
    "token" => "tok_slow"
  }.freeze

  def test_sync_false_returns_an_accepted_response
    @server.respond(200, ACCEPTED, "X-Cache" => "miss", "X-Quota-Cost" => "1")

    response = client.markdown(URL, sync: false, labels: { client: "acme" })

    assert_equal false, @server.last_request.json["sync"]
    assert_predicate response, :accepted?
    assert_equal "accepted", response.status
    assert_nil response.data
    assert_equal "tok_async", response.token
    assert_equal({ "client" => "acme" }, response.labels)
    assert_equal "miss", response.meta.cache
    assert_equal 1, response.meta.quota.cost
  end

  def test_accepted_prefers_the_token_header
    @server.respond(200, ACCEPTED, "X-Result-Token" => "tok_header")

    assert_equal "tok_header", client.html(URL, sync: false).token
  end

  def test_result_completed_is_typed_by_the_operation_hint
    @server.respond(200, ["a", "b"], "X-Result-Token" => "tok_async")

    response = client.result("tok_async", operation: "keywords")

    request = @server.last_request
    assert_equal "GET", request.method
    assert_equal "/result/tok_async", request.path
    assert_equal "Bearer #{API_KEY}", request["Authorization"]
    assert_equal "urlpipe-ruby/#{Urlpipe::VERSION}", request["User-Agent"]
    assert_predicate response, :completed?
    assert_equal %w[a b], response.data
  end

  def test_result_without_a_hint_parses_json_and_keeps_text
    @server.respond(200, { "title" => "Hi" }).respond(200, "# Markdown")

    assert_equal({ "title" => "Hi" }, client.result("t1").data)
    assert_equal "# Markdown", client.result("t2").data
  end

  def test_result_screenshot_hint_decodes_the_image
    png = "\x89PNG\r\n\x1A\nrest".b
    @server.respond(200, [png].pack("m0"), "X-Result-Url" => "https://urlpipe.dev/r/x.png")

    shot = client.result("tok", operation: :screenshot).data

    assert_equal png, shot.data
    assert_equal "https://urlpipe.dev/r/x.png", shot.result_url
  end

  def test_result_processing_is_a_response_not_an_error
    @server.respond(202, PROCESSING)

    response = client.result("tok_async")

    assert_predicate response, :processing?
    assert_nil response.data
    assert_equal "tok_async", response.token
    assert_equal({}, response.labels)
  end

  def test_result_504_processing_timeout_is_a_processing_response
    @server.respond(504, TIMEOUT_BODY)

    response = client.result("tok_slow")

    assert_predicate response, :processing?
    assert_equal "tok_slow", response.token
    assert_equal({}, response.labels)
  end

  def test_accepted_without_labels_has_an_empty_map
    @server.respond(200, { "token" => "tok_async", "status" => "accepted" })

    assert_equal({}, client.markdown(URL, sync: false).labels)
  end

  def test_wait_polls_until_completed
    @server.respond(202, PROCESSING).respond(202, PROCESSING).respond(200, "# Done")

    response = client.wait("tok_async", operation: "markdown", interval: 0.01)

    assert_equal "# Done", response.data
    assert_equal 3, @server.requests.size
    assert(@server.requests.all? { |request| request.path == "/result/tok_async" })
  end

  def test_wait_raises_wait_timeout_error_with_the_token
    3.times { @server.respond(202, PROCESSING) }

    error = assert_raises(Urlpipe::WaitTimeoutError) do
      client.wait("tok_async", timeout: 0.05, interval: 0.02)
    end

    assert_equal "tok_async", error.token
    assert_match(/tok_async/, error.message)
  end

  def test_wait_raises_the_analysis_failure
    @server.respond(202, PROCESSING).respond(422, { "error" => "The request timed out." })

    error = assert_raises(Urlpipe::AnalysisFailedError) { client.wait("tok_async") }

    assert_equal "The request timed out.", error.message
  end

  def test_sync_504_polls_the_result_and_returns_it
    @server.respond(504, TIMEOUT_BODY, "X-Result-Token" => "tok_slow")
           .respond(202, PROCESSING.merge("token" => "tok_slow"))
           .respond(200, { "url" => URL, "categories" => {} }, "X-Processing-Time-Ms" => "71234")

    response = client.lighthouse(URL)

    assert_equal %w[/lighthouse /result/tok_slow /result/tok_slow], @server.requests.map(&:path)
    assert_predicate response, :completed?
    assert_equal({ "url" => URL, "categories" => {} }, response.data)
    assert_equal 71_234, response.meta.processing_time_ms
  end

  def test_sync_504_types_a_screenshot_after_polling
    png = "\x89PNG\r\n\x1A\nrest".b
    @server.respond(504, TIMEOUT_BODY).respond(200, [png].pack("m0"))

    assert_equal png, client.screenshot(URL).data.data
  end

  def test_sync_504_raises_wait_timeout_error_after_wait_timeout
    @server.respond(504, TIMEOUT_BODY)
    5.times { @server.respond(202, PROCESSING) }

    error = assert_raises(Urlpipe::WaitTimeoutError) do
      client(wait_timeout: 0.05, poll_interval: 0.02).markdown(URL)
    end

    assert_equal "tok_slow", error.token
  end
end
