# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "securerandom"
require "uri"

module Urlpipe
  # A client for the URLpipe API. Every analysis method takes the URL first
  # and returns a Response. Calls are synchronous by default: the method
  # returns once the result is ready, however long the analysis takes.
  #
  #   client = Urlpipe::Client.new(api_key: "...")
  #   client.markdown("https://example.com").data # => "# Example Domain..."
  class Client
    DEFAULT_BASE_URL = "https://urlpipe.dev"
    USER_AGENT = "urlpipe-ruby/#{VERSION}".freeze

    TEXT_OPERATIONS = %w[markdown html summarize].freeze
    JSON_OPERATIONS = %w[meta keywords console lighthouse scrape].freeze

    RETRYABLE_STATUSES = [500, 502, 503].freeze
    MAX_RETRY_DELAY = 60

    NETWORK_ERRORS = [
      SocketError, SystemCallError, IOError, Timeout::Error,
      Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
      Net::HTTPBadResponse, OpenSSL::SSL::SSLError
    ].freeze

    # The raw HTTP exchange, before it becomes a Response or an error.
    RawResponse = Struct.new(:status, :headers, :text, keyword_init: true) do
      def json? = headers["content-type"].to_s.include?("json")
    end
    private_constant :RawResponse

    attr_reader :base_url, :timeout, :max_retries, :wait_timeout, :poll_interval

    # - +api_key+: a project API key; falls back to ENV["URLPIPE_API_KEY"]
    # - +timeout+: seconds per HTTP request (the API holds a sync request up
    #   to 60 s, so keep it above that)
    # - +max_retries+: automatic retries on connection errors, 500/502/503,
    #   rate_limited and concurrency_limit
    # - +wait_timeout+: how long a sync call or +wait+ keeps polling a long
    #   analysis before raising WaitTimeoutError
    # - +poll_interval+: seconds between polls of GET /result/:token
    def initialize(api_key: nil, base_url: DEFAULT_BASE_URL, timeout: 90, max_retries: 2,
                   wait_timeout: 300, poll_interval: 2)
      api_key = ENV.fetch("URLPIPE_API_KEY", nil) if api_key.nil? || api_key.to_s.strip.empty?
      if api_key.nil? || api_key.strip.empty?
        raise ConfigurationError,
              "Pass api_key: to Urlpipe::Client.new, or set URLPIPE_API_KEY. " \
              "Each project's API key is in the URLpipe dashboard."
      end

      @api_key = api_key.strip
      @base_url = base_url.to_s.sub(%r{/+\z}, "")
      @base_uri = URI(@base_url)
      @timeout = timeout
      @max_retries = Integer(max_retries)
      @wait_timeout = wait_timeout
      @poll_interval = poll_interval
    end

    def inspect
      "#<#{self.class.name} base_url=#{@base_url.inspect} timeout=#{@timeout} " \
        "max_retries=#{@max_retries} wait_timeout=#{@wait_timeout}>"
    end

    # The page as Markdown. +data+ is a String.
    def markdown(url, sync: true, max_age: nil, labels: nil, residential: nil, report_to: nil,
                 page_options: nil, idempotency_key: nil, extra: {})
      analyse("markdown", url, { sync:, max_age:, labels:, residential:, report_to:, page_options: },
              idempotency_key, extra)
    end

    # The rendered HTML document. +data+ is a String.
    def html(url, sync: true, max_age: nil, labels: nil, residential: nil, report_to: nil,
             page_options: nil, idempotency_key: nil, extra: {})
      analyse("html", url, { sync:, max_age:, labels:, residential:, report_to:, page_options: },
              idempotency_key, extra)
    end

    # A summary of the page, as Markdown. +data+ is a String.
    def summarize(url, sync: true, max_age: nil, labels: nil, residential: nil, report_to: nil,
                  page_options: nil, idempotency_key: nil, extra: {})
      analyse("summarize", url, { sync:, max_age:, labels:, residential:, report_to:, page_options: },
              idempotency_key, extra)
    end

    # A full-page screenshot. +data+ is a Screenshot (decoded bytes,
    # +mime_type+, +result_url+).
    def screenshot(url, sync: true, max_age: nil, labels: nil, residential: nil, report_to: nil,
                   page_options: nil, screenshot_options: nil, idempotency_key: nil, extra: {})
      analyse("screenshot", url,
              { sync:, max_age:, labels:, residential:, report_to:, page_options:, screenshot_options: },
              idempotency_key, extra)
    end

    # Page metadata. +data+ is a Hash: title, description, language,
    # main_image_url, favicon_url, author_name, feed_url, publication_date,
    # additional_author_information.
    def meta(url, sync: true, max_age: nil, labels: nil, residential: nil, report_to: nil,
             page_options: nil, idempotency_key: nil, extra: {})
      analyse("meta", url, { sync:, max_age:, labels:, residential:, report_to:, page_options: },
              idempotency_key, extra)
    end

    # The page's keywords, most relevant first. +data+ is an Array of Strings.
    def keywords(url, sync: true, max_age: nil, labels: nil, residential: nil, report_to: nil,
                 page_options: nil, idempotency_key: nil, extra: {})
      analyse("keywords", url, { sync:, max_age:, labels:, residential:, report_to:, page_options: },
              idempotency_key, extra)
    end

    # Console errors, warnings and uncaught exceptions. +data+ is an Array of
    # Hashes with "type" ("error", "warning" or "exception") and "text".
    def console(url, sync: true, max_age: nil, labels: nil, residential: nil, report_to: nil,
                page_options: nil, idempotency_key: nil, extra: {})
      analyse("console", url, { sync:, max_age:, labels:, residential:, report_to:, page_options: },
              idempotency_key, extra)
    end

    # A Lighthouse audit. +data+ is a Hash. +device+ is "mobile" (the API's
    # default) or "desktop".
    def lighthouse(url, sync: true, max_age: nil, labels: nil, residential: nil, report_to: nil,
                   device: nil, include_audits: nil, idempotency_key: nil, extra: {})
      analyse("lighthouse", url, { sync:, max_age:, labels:, residential:, report_to:, device:, include_audits: },
              idempotency_key, extra)
    end

    # Several operations off one page visit. +operations+ is an Array such as
    # ["markdown", "meta"]. +data+ is a Hash:
    # {"url" => ..., "operations" => {"markdown" => {"success", "result", "error", "cached"}}}.
    # A screenshot inside a scrape stays Base64, as the API returns it.
    def scrape(url, operations, sync: true, max_age: nil, labels: nil, residential: nil, report_to: nil,
               page_options: nil, device: nil, include_audits: nil, screenshot_options: nil,
               idempotency_key: nil, extra: {})
      analyse("scrape", url,
              { operations:, sync:, max_age:, labels:, residential:, report_to:, page_options:,
                device:, include_audits:, screenshot_options: },
              idempotency_key, extra)
    end

    # One GET /result/:token. Returns a completed Response (200) or a
    # processing one (202); raises for everything else.
    #
    # +operation+ names the operation that produced the token, so +data+ is
    # typed as that operation returns it. Without it, JSON stays parsed JSON
    # and text stays a String (a screenshot stays Base64: pass
    # <tt>operation: "screenshot"</tt> to get a Screenshot).
    def result(token, operation: nil)
      raw = execute(:get, "/result/#{URI.encode_www_form_component(token)}")

      case raw.status
      when 200 then completed(raw, operation&.to_s)
      when 202 then pending(raw, "processing", fallback_token: token)
      else
        if processing_timeout?(raw)
          pending(raw, "processing", fallback_token: token)
        else
          raise error_for(raw)
        end
      end
    end

    # Polls GET /result/:token every +interval+ seconds until the result is
    # ready, then returns the completed Response. Raises WaitTimeoutError
    # after +timeout+ seconds, or the API's error if the analysis failed.
    def wait(token, operation: nil, timeout: @wait_timeout, interval: @poll_interval)
      deadline = monotonic_now + timeout

      loop do
        response = result(token, operation: operation)
        return response if response.completed?

        if monotonic_now + interval > deadline
          raise WaitTimeoutError.new(
            "The result for #{token} was not ready within #{timeout} seconds. " \
            "It keeps running: collect it later with client.wait(#{token.inspect}).",
            token: token
          )
        end

        sleep(interval)
      end
    end

    private

    def analyse(operation, url, options, idempotency_key, extra)
      body = { "url" => url }
      options.each { |key, value| body[key.to_s] = value unless value.nil? }
      (extra || {}).each { |key, value| body[key.to_s] = value }

      idempotency_key ||= SecureRandom.uuid if @max_retries.positive?
      raw = execute(:post, "/#{operation}", body: body, idempotency_key: idempotency_key)

      if raw.status == 200
        sync?(body["sync"]) ? completed(raw, operation) : pending(raw, "accepted")
      elsif processing_timeout?(raw) && (token = json_body(raw)["token"])
        wait(token, operation: operation)
      else
        raise error_for(raw)
      end
    end

    def sync?(value) = [true, "true"].include?(value)

    def completed(raw, operation)
      Response.new(
        status: "completed",
        data: typed_data(raw, operation),
        token: raw.headers["x-result-token"],
        labels: header_labels(raw) || {},
        meta: Meta.from_headers(raw.headers)
      )
    end

    def pending(raw, status, fallback_token: nil)
      body = json_body(raw)
      Response.new(
        status: status,
        data: nil,
        token: raw.headers["x-result-token"] || body["token"] || fallback_token,
        labels: header_labels(raw) || (body["labels"].is_a?(Hash) ? body["labels"] : {}),
        meta: Meta.from_headers(raw.headers)
      )
    end

    def typed_data(raw, operation)
      if TEXT_OPERATIONS.include?(operation)
        raw.text
      elsif operation == "screenshot"
        Screenshot.from_base64(raw.text, result_url: raw.headers["x-result-url"])
      elsif JSON_OPERATIONS.include?(operation) || (operation.nil? && raw.json?)
        parse_result_json(raw)
      else
        raw.text
      end
    end

    def parse_result_json(raw)
      JSON.parse(raw.text)
    rescue JSON::ParserError => e
      raise Error.new("The API answered #{raw.status} with a body that is not valid JSON: #{e.message}",
                      status: raw.status, body: raw.text)
    end

    def header_labels(raw)
      value = raw.headers["x-labels"]
      return nil if value.nil? || value.strip.empty?

      JSON.parse(value)
    rescue JSON::ParserError
      nil
    end

    def json_body(raw)
      parsed = ErrorFactory.parse_json(raw.text)
      parsed.is_a?(Hash) ? parsed : {}
    end

    def processing_timeout?(raw)
      raw.status == 504 && json_body(raw)["error"] == "processing_timeout"
    end

    def error_for(raw)
      ErrorFactory.build(status: raw.status, text: raw.text, headers: raw.headers)
    end

    # Sends the request, retrying what is safe to retry. The same
    # Idempotency-Key goes out on every attempt, so a retry can never run or
    # bill the work twice.
    def execute(method, path, body: nil, idempotency_key: nil)
      attempt = 0

      loop do
        begin
          raw = perform(method, path, body, idempotency_key)
        rescue ConnectionError
          raise if attempt >= @max_retries

          sleep(backoff(attempt))
          attempt += 1
          next
        end

        delay = retry_delay(raw, attempt)
        return raw if delay.nil? || attempt >= @max_retries

        sleep(delay)
        attempt += 1
      end
    end

    def retry_delay(raw, attempt)
      return backoff(attempt) if RETRYABLE_STATUSES.include?(raw.status)
      return nil unless raw.status == 429

      case json_body(raw)["error"]
      when "rate_limited"
        retry_after = ErrorFactory.retry_after(raw.headers, json_body(raw))
        [retry_after || 1, MAX_RETRY_DELAY].min
      when "concurrency_limit"
        backoff(attempt)
      end
    end

    def backoff(attempt) = [2**attempt, MAX_RETRY_DELAY].min

    def perform(method, path, body, idempotency_key)
      uri = @base_uri.dup
      uri.path = "#{@base_uri.path}#{path}"

      request = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["User-Agent"] = USER_AGENT
      request["Accept"] = "*/*"
      request["Idempotency-Key"] = idempotency_key if idempotency_key
      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end

      response = http_for(uri).start { |http| http.request(request) }
      headers = response.each_header.to_h { |name, value| [name.downcase, value] }
      text = (response.body || +"").dup.force_encoding(Encoding::UTF_8)
      RawResponse.new(status: response.code.to_i, headers: headers, text: text)
    rescue *NETWORK_ERRORS => e
      raise ConnectionError, "Could not reach #{@base_url}: #{e.class}: #{e.message}"
    end

    def http_for(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http.write_timeout = @timeout
      http.max_retries = 0
      http
    end

    def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
