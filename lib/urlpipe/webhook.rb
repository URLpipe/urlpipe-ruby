# frozen_string_literal: true

require "json"
require "openssl"

module Urlpipe
  # Verifies signed webhook deliveries. No Client needed.
  #
  #   # Rails
  #   payload = Urlpipe::Webhook.verify(request.raw_post, request.headers,
  #                                     ENV["URLPIPE_WEBHOOK_SECRET"])
  #   payload["token"] # => "0Zx3...9aQ"
  #
  # Give it the RAW request body, exactly the bytes received. Parsed and
  # re-serialized JSON has different bytes, and the signature will not match.
  module Webhook
    TIMESTAMP_HEADER = "X-URLpipe-Timestamp"
    SIGNATURE_HEADER = "X-URLpipe-Signature"
    DEFAULT_TOLERANCE = 300

    module_function

    # Checks the delivery's signature and freshness and returns the parsed
    # payload, a Hash with "token", "operation", "labels", "success",
    # "result", "result_url", "error" and "meta".
    #
    # - +raw_body+: the request body as received (a String, or an IO)
    # - +headers+: the request headers. Accepts a plain Hash, Rails'
    #   +request.headers+, a Rack env (+HTTP_X_URLPIPE_SIGNATURE+) or any
    #   object with +[]+; names are matched case-insensitively.
    # - +secret+: the project's signing secret (+whsec_...+), used as-is
    # - +tolerance+: seconds a timestamp may be off from now, either way
    #
    # Raises WebhookVerificationError with the reason when the delivery
    # does not verify.
    def verify(raw_body, headers, secret, tolerance: DEFAULT_TOLERANCE)
      raise WebhookVerificationError, "No webhook signing secret was given." if secret.to_s.empty?

      body = read_body(raw_body)
      timestamp = header(headers, TIMESTAMP_HEADER).to_s.strip
      signature = header(headers, SIGNATURE_HEADER).to_s.strip

      raise WebhookVerificationError, "The #{SIGNATURE_HEADER} header is missing." if signature.empty?
      raise WebhookVerificationError, "The #{TIMESTAMP_HEADER} header is missing." if timestamp.empty?
      unless timestamp.match?(/\A\d+\z/)
        raise WebhookVerificationError, "The #{TIMESTAMP_HEADER} header is not a Unix timestamp."
      end

      age = Time.now.to_i - Integer(timestamp, 10)
      if age.abs > tolerance
        raise WebhookVerificationError,
              "The delivery's timestamp is #{age.abs} seconds #{age.negative? ? "ahead" : "old"}, " \
              "outside the #{tolerance}-second tolerance."
      end

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, "#{timestamp}.".b + body)
      unless candidates(signature).any? { |candidate| OpenSSL.secure_compare(candidate, expected) }
        raise WebhookVerificationError, "No v1 signature in #{SIGNATURE_HEADER} matches this body and secret."
      end

      parse(body)
    end

    def read_body(raw_body)
      body = raw_body.respond_to?(:read) ? raw_body.read.tap { raw_body.rewind if raw_body.respond_to?(:rewind) } : raw_body
      body.to_s.b
    end

    # The v1 values of a "v1=<hex>,v1=<hex>" header; other schemes are ignored.
    def candidates(signature)
      signature.split(",").filter_map do |part|
        scheme, value = part.strip.split("=", 2)
        value.strip.downcase if scheme == "v1" && value
      end
    end

    def parse(body)
      payload = JSON.parse(body.dup.force_encoding(Encoding::UTF_8))
      raise WebhookVerificationError, "The delivery body is not a JSON object." unless payload.is_a?(Hash)

      payload
    rescue JSON::ParserError => e
      raise WebhookVerificationError, "The delivery body is not valid JSON: #{e.message}"
    end

    def header(headers, name)
      normalized = normalize(name)

      if headers.respond_to?(:[])
        [name, name.downcase, "HTTP_#{normalized}"].each do |key|
          value = safe_lookup(headers, key)
          return header_value(value) unless value.nil?
        end
      end

      return nil unless headers.respond_to?(:each)

      headers.each do |key, value|
        return header_value(value) if normalize(key.to_s) == normalized
      end
      nil
    end

    def normalize(key)
      key.upcase.tr("-", "_").delete_prefix("HTTP_")
    end

    def safe_lookup(headers, key)
      headers[key]
    rescue StandardError
      nil
    end

    def header_value(value)
      value.is_a?(Array) ? value.join(",") : value.to_s
    end
  end
end
