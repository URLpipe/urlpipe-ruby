# frozen_string_literal: true

require "json"

module Urlpipe
  # What an analysis cost and what is left of the month's allowance.
  # +limit+ and +remaining+ are Integers, or the String "unlimited".
  Quota = Struct.new(:cost, :limit, :remaining, :overage, :resets_at, keyword_init: true)

  # The response's metadata headers, parsed. A header that was not sent is
  # +nil+ (+idempotent_replayed+ is always true or false).
  #
  # - +cache+: "hit", "miss" or (for /scrape) "partial"
  # - +cache_age+: seconds, when served from cache
  # - +processing_time_ms+: once the work has finished
  # - +quota+: a Quota
  # - +concurrency_limit+: Integer or "unlimited"
  # - +result_url+: screenshots only, a link to the image that needs no key
  # - +idempotent_replayed+: +true+ when this answers an earlier request with
  #   the same Idempotency-Key, +false+ otherwise
  Meta = Struct.new(
    :cache, :cache_age, :processing_time_ms, :quota, :concurrency_limit,
    :result_url, :idempotent_replayed,
    keyword_init: true
  ) do
    # +headers+ is a Hash of lowercase header names to values.
    def self.from_headers(headers)
      new(
        cache: headers["x-cache"],
        cache_age: integer_or_nil(headers["x-cache-age"]),
        processing_time_ms: integer_or_nil(headers["x-processing-time-ms"]),
        quota: Quota.new(
          cost: integer_or_given(headers["x-quota-cost"]),
          limit: integer_or_given(headers["x-quota-limit"]),
          remaining: integer_or_given(headers["x-quota-remaining"]),
          overage: integer_or_given(headers["x-quota-overage"]),
          resets_at: headers["x-quota-reset"]
        ),
        concurrency_limit: integer_or_given(headers["x-concurrency-limit"]),
        result_url: headers["x-result-url"],
        idempotent_replayed: headers["idempotent-replayed"].to_s.strip.casecmp?("true")
      )
    end

    def self.integer_or_nil(value)
      value = value&.strip
      value&.match?(/\A-?\d+\z/) ? Integer(value, 10) : nil
    end

    def self.integer_or_given(value)
      integer_or_nil(value) || value&.strip
    end
  end

  # What every method returns.
  #
  # - +status+: "completed", "accepted" (an async request was accepted) or
  #   "processing" (GET /result/:token is still working on it)
  # - +data+: the result when completed, +nil+ otherwise
  # - +token+: the request's result token
  # - +labels+: the labels the request was made with; {} when it had none
  # - +meta+: a Meta
  Response = Struct.new(:status, :data, :token, :labels, :meta, keyword_init: true) do
    def completed? = status == "completed"
    def accepted? = status == "accepted"
    def processing? = status == "processing"
  end
end
