# frozen_string_literal: true

require "json"

module Urlpipe
  # Base class of every error this library raises.
  #
  # - +status+: the HTTP status, when the error came from a response
  # - +code+: the body's +error+ value when it is a machine-readable code
  #   (+"invalid_url"+, +"quota_exceeded"+, ...)
  # - +body+: the parsed JSON body, or the raw text when it was not JSON
  # - +token+: the result token, when the body carried one
  class Error < StandardError
    attr_reader :status, :code, :body, :token

    def initialize(message = nil, status: nil, code: nil, body: nil, token: nil)
      super(message)
      @status = status
      @code = code
      @body = body
      @token = token
    end
  end

  # No API key was given and URLPIPE_API_KEY is not set.
  class ConfigurationError < Error; end

  # 401: the API key is missing or not an active project key.
  class AuthenticationError < Error; end

  # 403 email_unverified: the key is valid, but the account's email address
  # has not been confirmed yet.
  class EmailUnverifiedError < Error; end

  # 422 with a parameter code: invalid_url, invalid_max_age, invalid_options,
  # invalid_labels, invalid_idempotency_key, idempotency_key_reused, or a
  # report_to the API will not deliver to.
  class InvalidRequestError < Error; end

  # 422 whose error is a sentence: the page could not be analysed. The
  # sentence is the message. A /scrape where every operation failed keeps the
  # whole scrape object on +body+.
  class AnalysisFailedError < Error; end

  # 429 quota_exceeded (Free plan only): the month's credits are spent.
  class QuotaExceededError < Error
    attr_reader :limit, :used, :needed, :resets_at

    def initialize(message = nil, limit: nil, used: nil, needed: nil, resets_at: nil, **rest)
      super(message, **rest)
      @limit = limit
      @used = used
      @needed = needed
      @resets_at = resets_at
    end
  end

  # 429 concurrency_limit: too many of your requests are already running.
  class ConcurrencyLimitError < Error
    attr_reader :limit, :running

    def initialize(message = nil, limit: nil, running: nil, **rest)
      super(message, **rest)
      @limit = limit
      @running = running
    end
  end

  # 429 rate_limited: sending too fast. +retry_after+ is in seconds.
  class RateLimitedError < Error
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil, **rest)
      super(message, **rest)
      @retry_after = retry_after
    end
  end

  # 404 not_found: no result for this token under your project.
  class NotFoundError < Error; end

  # 410 stale: the result is older than the 30-day retention window.
  class StaleResultError < Error; end

  # A 5xx response.
  class ServerError < Error; end

  # The API could not be reached: DNS, refused or dropped connection, TLS,
  # or a request that outlived +timeout+.
  class ConnectionError < Error; end

  # +wait+ (or a sync call that timed out on the server) ran out of
  # +wait_timeout+. The analysis may still finish: keep +token+.
  class WaitTimeoutError < Error; end

  # A webhook delivery failed signature verification. The message says why.
  class WebhookVerificationError < Error; end

  # Builds the right error from an HTTP error response.
  module ErrorFactory
    CODE_PATTERN = /\A[a-z][a-z0-9_]*\z/
    INVALID_REQUEST_CODES = %w[
      invalid_url invalid_max_age invalid_options invalid_labels
      invalid_idempotency_key idempotency_key_reused
    ].freeze

    DEFAULT_MESSAGES = {
      AuthenticationError => "The API key is missing or not an active project key. " \
                             "Copy your project's key from the dashboard.",
      EmailUnverifiedError => "Confirm the email address on this account before using the API. " \
                              "The link is in the email we sent when you signed up.",
      NotFoundError => "No result for this token under this project.",
      StaleResultError => "This result is older than the 30-day retention window. Run a new analysis."
    }.freeze

    module_function

    def build(status:, text:, headers: {})
      parsed = parse_json(text)
      hash = parsed.is_a?(Hash) ? parsed : {}
      error_value = hash["error"].is_a?(String) ? hash["error"] : nil
      code = error_value if error_value&.match?(CODE_PATTERN)

      klass, extra = classify(status, code, error_value, hash, headers)
      message = message_for(klass, hash, error_value, code, status, text)

      klass.new(
        message,
        status: status,
        code: code,
        body: parsed.nil? ? text : parsed,
        token: hash["token"].is_a?(String) ? hash["token"] : headers["x-result-token"],
        **extra
      )
    end

    def parse_json(text)
      return nil if text.nil? || text.strip.empty?

      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end

    def classify(status, code, error_value, hash, headers)
      case status
      when 401 then [AuthenticationError, {}]
      when 403 then [code == "email_unverified" ? EmailUnverifiedError : Error, {}]
      when 404 then [NotFoundError, {}]
      when 410 then [StaleResultError, {}]
      when 422
        [invalid_request?(error_value) ? InvalidRequestError : AnalysisFailedError, {}]
      when 429 then classify_429(code, hash, headers)
      when 500..599 then [ServerError, {}]
      else [Error, {}]
      end
    end

    def classify_429(code, hash, headers)
      case code
      when "quota_exceeded"
        [QuotaExceededError,
         { limit: hash["limit"], used: hash["used"], needed: hash["needed"], resets_at: hash["resets_at"] }]
      when "concurrency_limit"
        [ConcurrencyLimitError, { limit: hash["limit"], running: hash["running"] }]
      when "rate_limited"
        [RateLimitedError, { retry_after: retry_after(headers, hash) }]
      else
        [Error, {}]
      end
    end

    def invalid_request?(error_value)
      return false unless error_value

      INVALID_REQUEST_CODES.include?(error_value) || error_value.start_with?("report_to")
    end

    def retry_after(headers, hash)
      value = headers["retry-after"]
      return Integer(value, 10) if value.is_a?(String) && value.strip.match?(/\A\d+\z/)

      hash["retry_after"].is_a?(Integer) ? hash["retry_after"] : nil
    end

    def message_for(klass, hash, error_value, code, status, text)
      return hash["message"] if hash["message"].is_a?(String) && !hash["message"].empty?
      return error_value if error_value && !error_value.empty? && code.nil?
      return scrape_failure_message(hash) if klass == AnalysisFailedError && hash["operations"].is_a?(Hash)
      return DEFAULT_MESSAGES[klass] if DEFAULT_MESSAGES.key?(klass)
      return "The API refused the request with HTTP #{status} (#{code})." if code

      snippet = text.to_s.strip[0, 200]
      snippet.empty? ? "HTTP #{status}" : "HTTP #{status}: #{snippet}"
    end

    def scrape_failure_message(hash)
      details = hash["operations"].map do |name, entry|
        error = entry.is_a?(Hash) ? entry["error"] : nil
        error ? "#{name}: #{error}" : name
      end
      "Every operation failed: #{details.join("; ")}"
    end
  end
end
