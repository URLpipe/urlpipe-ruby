# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class WebhookTest < Minitest::Test
  SECRET = "whsec_test_secret"
  OLD_SECRET = "whsec_old_secret"
  BODY = '{"token":"0Zx3","operation":"markdown","labels":{"client":"acme"},"success":true,' \
         '"result":"# Example","result_url":null,"error":null,"meta":{"cache":"miss"}}'

  def sign(body, timestamp, secret = SECRET)
    OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
  end

  def headers(signature, timestamp = Time.now.to_i)
    { "X-URLpipe-Timestamp" => timestamp.to_s, "X-URLpipe-Signature" => signature }
  end

  def verify(body, headers, **options)
    Urlpipe::Webhook.verify(body, headers, SECRET, **options)
  end

  def assert_rejected(pattern, &block)
    error = assert_raises(Urlpipe::WebhookVerificationError, &block)
    assert_match pattern, error.message
  end

  def test_valid_delivery_returns_the_payload
    now = Time.now.to_i

    payload = verify(BODY, headers("v1=#{sign(BODY, now)}", now))

    assert_equal "0Zx3", payload["token"]
    assert_equal "markdown", payload["operation"]
    assert_equal({ "client" => "acme" }, payload["labels"])
    assert_equal true, payload["success"]
    assert_equal "# Example", payload["result"]
    assert_equal({ "cache" => "miss" }, payload["meta"])
  end

  def test_tampered_body_is_rejected
    now = Time.now.to_i

    assert_rejected(/No v1 signature/) do
      verify(BODY.sub("# Example", "# Evil"), headers("v1=#{sign(BODY, now)}", now))
    end
  end

  def test_wrong_secret_is_rejected
    now = Time.now.to_i

    assert_rejected(/No v1 signature/) do
      verify(BODY, headers("v1=#{sign(BODY, now, "whsec_other")}", now))
    end
  end

  def test_stale_timestamp_is_rejected
    old = Time.now.to_i - 301

    assert_rejected(/outside the 300-second tolerance/) { verify(BODY, headers("v1=#{sign(BODY, old)}", old)) }
  end

  def test_future_timestamp_is_rejected
    ahead = Time.now.to_i + 600

    assert_rejected(/ahead/) { verify(BODY, headers("v1=#{sign(BODY, ahead)}", ahead)) }
  end

  def test_tolerance_is_configurable
    old = Time.now.to_i - 301

    assert_equal "0Zx3", verify(BODY, headers("v1=#{sign(BODY, old)}", old), tolerance: 600)["token"]
  end

  def test_rotation_second_signature_matches
    now = Time.now.to_i
    header = "v1=#{sign(BODY, now, OLD_SECRET)},v1=#{sign(BODY, now)}"

    assert_equal "0Zx3", verify(BODY, headers(header, now))["token"]
  end

  def test_unknown_schemes_are_ignored
    now = Time.now.to_i
    header = "v2=#{sign(BODY, now)}, v1=#{sign(BODY, now)}"

    assert_equal "0Zx3", verify(BODY, headers(header, now))["token"]
  end

  def test_only_unknown_schemes_is_rejected
    now = Time.now.to_i

    assert_rejected(/No v1 signature/) { verify(BODY, headers("v2=#{sign(BODY, now)}", now)) }
  end

  def test_missing_headers_are_rejected
    assert_rejected(/X-URLpipe-Signature header is missing/) { verify(BODY, {}) }
    assert_rejected(/X-URLpipe-Timestamp header is missing/) { verify(BODY, { "X-URLpipe-Signature" => "v1=ab" }) }
    assert_rejected(/not a Unix timestamp/) { verify(BODY, headers("v1=ab", "yesterday")) }
  end

  def test_accepts_rack_env_style_headers
    now = Time.now.to_i
    env = { "HTTP_X_URLPIPE_TIMESTAMP" => now.to_s, "HTTP_X_URLPIPE_SIGNATURE" => "v1=#{sign(BODY, now)}",
            "rack.input" => StringIO.new(BODY) }

    assert_equal "0Zx3", verify(BODY, env)["token"]
  end

  def test_accepts_lowercase_and_symbol_header_names
    now = Time.now.to_i
    signature = "v1=#{sign(BODY, now)}"

    assert_equal "0Zx3", verify(BODY, { "x-urlpipe-timestamp" => now.to_s, "x-urlpipe-signature" => signature })["token"]
    assert_equal "0Zx3", verify(BODY, { x_urlpipe_timestamp: now.to_s, x_urlpipe_signature: signature })["token"]
  end

  # Rails' request.headers answers [] with HTTP-style names and iterates as
  # the Rack env; this stands in for it.
  class RailsLikeHeaders
    def initialize(env) = @env = env

    def [](key)
      name = key.to_s
      name = "HTTP_#{name.upcase.tr("-", "_")}" unless name.start_with?("HTTP_") || name.include?(".")
      @env[name]
    end

    def each(&) = @env.each(&)
  end

  def test_accepts_rails_request_headers
    now = Time.now.to_i
    rails = RailsLikeHeaders.new("HTTP_X_URLPIPE_TIMESTAMP" => now.to_s,
                                 "HTTP_X_URLPIPE_SIGNATURE" => "v1=#{sign(BODY, now)}")

    assert_equal "0Zx3", verify(BODY, rails)["token"]
  end

  def test_accepts_an_io_body_and_rewinds_it
    now = Time.now.to_i
    io = StringIO.new(BODY)

    assert_equal "0Zx3", verify(io, headers("v1=#{sign(BODY, now)}", now))["token"]
    assert_equal BODY, io.read
  end

  def test_signs_the_raw_bytes_of_a_non_ascii_body
    body = '{"token":"t","result":"Café ☕"}'.b
    now = Time.now.to_i

    assert_equal "Café ☕", verify(body, headers("v1=#{sign(body, now)}", now))["result"]
  end
end
