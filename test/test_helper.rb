# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "urlpipe"
require "minitest/autorun"
require_relative "support/stub_server"

class UrlpipeTest < Minitest::Test
  API_KEY = "test_key_123"

  QUOTA_HEADERS = {
    "X-Result-Token" => "tok_123",
    "X-Cache" => "hit",
    "X-Cache-Age" => "5400",
    "X-Processing-Time-Ms" => "12",
    "X-Quota-Cost" => "0",
    "X-Quota-Limit" => "1000",
    "X-Quota-Remaining" => "943",
    "X-Quota-Overage" => "0",
    "X-Quota-Reset" => "2026-08-31T23:59:59Z",
    "X-Concurrency-Limit" => "3"
  }.freeze

  def setup
    @server = StubServer.new
  end

  def teardown
    @server.shutdown
  end

  def client(**options)
    Urlpipe::Client.new(api_key: API_KEY, base_url: @server.url, poll_interval: 0.01, **options)
  end
end
