# frozen_string_literal: true

require_relative "test_helper"

class OperationsTest < UrlpipeTest
  URL = "https://example.com"

  def assert_standard_request(request, path)
    assert_equal "POST", request.method
    assert_equal path, request.path
    assert_equal "Bearer #{API_KEY}", request["Authorization"]
    assert_equal "urlpipe-ruby/#{Urlpipe::VERSION}", request["User-Agent"]
    assert_match %r{\Aapplication/json}, request["Content-Type"]
    assert_equal URL, request.json["url"]
    assert_equal true, request.json["sync"]
  end

  def test_markdown_returns_the_text_and_parses_headers
    @server.respond(200, "# Example Domain\n\nCafé", QUOTA_HEADERS.merge("X-Labels" => '{"client":"acme"}'))

    response = client.markdown(URL)

    assert_standard_request(@server.last_request, "/markdown")
    assert_predicate response, :completed?
    assert_equal "# Example Domain\n\nCafé", response.data
    assert_equal Encoding::UTF_8, response.data.encoding
    assert_equal "tok_123", response.token
    assert_equal({ "client" => "acme" }, response.labels)

    meta = response.meta
    assert_equal "hit", meta.cache
    assert_equal 5400, meta.cache_age
    assert_equal 12, meta.processing_time_ms
    assert_equal 0, meta.quota.cost
    assert_equal 1000, meta.quota.limit
    assert_equal 943, meta.quota.remaining
    assert_equal 0, meta.quota.overage
    assert_equal "2026-08-31T23:59:59Z", meta.quota.resets_at
    assert_equal 3, meta.concurrency_limit
    assert_nil meta.result_url
    assert_equal false, meta.idempotent_replayed
  end

  def test_unlimited_plan_headers_stay_strings
    @server.respond(200, "ok", "X-Quota-Limit" => "unlimited", "X-Quota-Remaining" => "unlimited",
                               "X-Concurrency-Limit" => "unlimited", "Idempotent-Replayed" => "true")

    meta = client.markdown(URL).meta

    assert_equal "unlimited", meta.quota.limit
    assert_equal "unlimited", meta.quota.remaining
    assert_equal "unlimited", meta.concurrency_limit
    assert_equal true, meta.idempotent_replayed
  end

  def test_unparseable_labels_header_is_an_empty_map
    @server.respond(200, "ok", "X-Labels" => "{not json")

    assert_equal({}, client.markdown(URL).labels)
  end

  def test_include_audits_passes_through_as_given
    @server.respond(200, {})

    client.lighthouse(URL, include_audits: "true")

    assert_equal "true", @server.last_request.json["include_audits"]
  end

  def test_extra_may_override_sync_and_the_call_follows_it
    @server.respond(200, { "token" => "tok_x", "status" => "accepted" })

    response = client.markdown(URL, extra: { sync: false })

    assert_equal false, @server.last_request.json["sync"]
    assert_predicate response, :accepted?
    assert_equal "tok_x", response.token
  end

  def test_missing_headers_are_nil
    @server.respond(200, "ok")

    response = client.markdown(URL)

    assert_nil response.token
    assert_equal({}, response.labels)
    assert_equal false, response.meta.idempotent_replayed
    assert_nil response.meta.cache
    assert_nil response.meta.cache_age
    assert_nil response.meta.processing_time_ms
    assert_nil response.meta.quota.cost
    assert_nil response.meta.quota.limit
    assert_nil response.meta.quota.resets_at
    assert_nil response.meta.concurrency_limit
  end

  def test_html
    @server.respond(200, "<html><body>Hi</body></html>", QUOTA_HEADERS)

    response = client.html(URL)

    assert_standard_request(@server.last_request, "/html")
    assert_equal "<html><body>Hi</body></html>", response.data
  end

  def test_summarize
    @server.respond(200, "A short **summary**.", QUOTA_HEADERS)

    response = client.summarize(URL)

    assert_standard_request(@server.last_request, "/summarize")
    assert_equal "A short **summary**.", response.data
  end

  def test_meta_returns_a_hash
    metadata = { "title" => "Example Domain", "description" => nil, "language" => "en",
                 "additional_author_information" => { "twitter" => "@janedoe" } }
    @server.respond(200, metadata, QUOTA_HEADERS)

    response = client.meta(URL)

    assert_standard_request(@server.last_request, "/meta")
    assert_equal metadata, response.data
  end

  def test_keywords_returns_an_array_of_strings
    @server.respond(200, ["example domain", "IANA"], QUOTA_HEADERS)

    response = client.keywords(URL)

    assert_standard_request(@server.last_request, "/keywords")
    assert_equal ["example domain", "IANA"], response.data
  end

  def test_console_returns_entries
    entries = [{ "type" => "error", "text" => "Failed to fetch" }, { "type" => "exception", "text" => "boom" }]
    @server.respond(200, entries, QUOTA_HEADERS)

    response = client.console(URL)

    assert_standard_request(@server.last_request, "/console")
    assert_equal entries, response.data
  end

  def test_lighthouse_sends_device_and_include_audits
    report = { "url" => URL, "categories" => { "performance" => { "score" => 0.98 } } }
    @server.respond(200, report, QUOTA_HEADERS)

    response = client.lighthouse(URL, device: "desktop", include_audits: true)

    request = @server.last_request
    assert_standard_request(request, "/lighthouse")
    assert_equal "desktop", request.json["device"]
    assert_equal true, request.json["include_audits"]
    assert_equal report, response.data
  end

  def test_scrape_sends_operations_and_options
    result = { "url" => URL, "operations" => {
      "markdown" => { "success" => true, "result" => "# Hi", "cached" => false },
      "meta" => { "success" => false, "result" => nil, "error" => "The page is too big to be processed.",
                  "cached" => false }
    } }
    @server.respond(200, result, QUOTA_HEADERS.merge("X-Cache" => "partial"))

    response = client.scrape(URL, %w[markdown meta screenshot], device: "mobile",
                                                                screenshot_options: { format: "webp" })

    request = @server.last_request
    assert_standard_request(request, "/scrape")
    assert_equal %w[markdown meta screenshot], request.json["operations"]
    assert_equal({ "format" => "webp" }, request.json["screenshot_options"])
    assert_equal "mobile", request.json["device"]
    assert_equal result, response.data
    assert_equal "partial", response.meta.cache
  end

  def test_common_options_are_sent_only_when_given
    @server.respond(200, "ok")

    client.markdown(URL, max_age: "3 days", labels: { client: "acme" }, residential: true,
                         report_to: "https://hooks.example.com/urlpipe",
                         page_options: { block_cookie_banners: true, remove_selectors: ["#ad"] })

    assert_equal(
      { "url" => URL, "sync" => true, "max_age" => "3 days", "labels" => { "client" => "acme" },
        "residential" => true, "report_to" => "https://hooks.example.com/urlpipe",
        "page_options" => { "block_cookie_banners" => true, "remove_selectors" => ["#ad"] } },
      @server.last_request.json
    )
  end

  def test_bare_call_sends_only_url_and_sync
    @server.respond(200, "ok")

    client.html(URL)

    assert_equal({ "url" => URL, "sync" => true }, @server.last_request.json)
  end

  def test_extra_params_are_merged_into_the_body
    @server.respond(200, "ok")

    client.markdown(URL, max_age: 60, extra: { future_option: "on", max_age: 0 })

    assert_equal({ "url" => URL, "sync" => true, "max_age" => 0, "future_option" => "on" },
                 @server.last_request.json)
  end

  def test_idempotency_key_is_a_header_not_a_body_param
    @server.respond(200, "ok")

    client.markdown(URL, idempotency_key: "my-key-1")

    request = @server.last_request
    assert_equal "my-key-1", request["Idempotency-Key"]
    assert_equal({ "url" => URL, "sync" => true }, request.json)
  end

  def test_a_key_is_generated_per_call_when_retries_are_on
    @server.respond(200, "ok").respond(200, "ok")

    client.markdown(URL)
    client.markdown(URL)

    keys = @server.requests.map { |request| request["Idempotency-Key"] }
    keys.each { |key| assert_match(/\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/, key) }
    refute_equal keys[0], keys[1]
  end

  def test_no_key_is_generated_when_retries_are_off
    @server.respond(200, "ok")

    client(max_retries: 0).markdown(URL)

    assert_equal [false], @server.requests.map { |request| request.headers.key?("idempotency-key") }
  end

  def test_base_url_with_a_path_prefix_and_trailing_slash
    @server.respond(200, "ok")

    Urlpipe::Client.new(api_key: API_KEY, base_url: "#{@server.url}/proxy/").markdown(URL)

    assert_equal "/proxy/markdown", @server.last_request.path
  end
end
