# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < UrlpipeTest
  def with_env(value)
    previous = ENV.fetch("URLPIPE_API_KEY", nil)
    value.nil? ? ENV.delete("URLPIPE_API_KEY") : ENV["URLPIPE_API_KEY"] = value
    yield
  ensure
    previous.nil? ? ENV.delete("URLPIPE_API_KEY") : ENV["URLPIPE_API_KEY"] = previous
  end

  def test_defaults
    c = Urlpipe::Client.new(api_key: "k")

    assert_equal "https://urlpipe.dev", c.base_url
    assert_equal 90, c.timeout
    assert_equal 2, c.max_retries
    assert_equal 300, c.wait_timeout
    assert_equal 2, c.poll_interval
  end

  def test_missing_api_key_raises_at_construction
    with_env(nil) do
      error = assert_raises(Urlpipe::ConfigurationError) { Urlpipe::Client.new }
      assert_match(/URLPIPE_API_KEY/, error.message)
      assert_kind_of Urlpipe::Error, error
    end
  end

  def test_api_key_falls_back_to_the_environment
    @server.respond(200, "ok")

    with_env("env_key") do
      Urlpipe::Client.new(base_url: @server.url).markdown("https://example.com")
    end

    assert_equal "Bearer env_key", @server.last_request["Authorization"]
  end

  def test_inspect_hides_the_api_key
    assert_equal '#<Urlpipe::Client base_url="https://urlpipe.dev" timeout=90 max_retries=2 wait_timeout=300>',
                 Urlpipe::Client.new(api_key: "secret_key_value").inspect
  end

  def test_unreachable_api_raises_connection_error
    port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
    c = Urlpipe::Client.new(api_key: "k", base_url: "http://127.0.0.1:#{port}", max_retries: 0)

    error = assert_raises(Urlpipe::ConnectionError) { c.markdown("https://example.com") }
    assert_match(/Could not reach/, error.message)
  end
end
