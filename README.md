# urlpipe

Turn any URL into clean Markdown, rendered HTML, a full-page screenshot, metadata, a summary, keywords, console errors or a Lighthouse audit, from Ruby. Pages are rendered in real Chrome, so JavaScript-heavy sites come back complete.

This is the official Ruby client for [URLpipe](https://urlpipe.dev). It has no runtime dependencies and runs on Ruby 3.1 and later.

## Install

```sh
bundle add urlpipe
```

or `gem install urlpipe`.

## Quickstart

Get an API key from a project in the [dashboard](https://urlpipe.dev) (the Free plan includes 1,000 credits a month, no card) and put it in `URLPIPE_API_KEY`:

```ruby
require "urlpipe"

client = Urlpipe::Client.new # reads ENV["URLPIPE_API_KEY"]

response = client.markdown("https://example.com")
puts response.data           # "# Example Domain\n\n..."
response.meta.quota.remaining # => 943
```

Every call waits for the result and hands it back in `response.data`. Cached results and failed calls cost nothing.

## The client

```ruby
Urlpipe::Client.new(
  api_key: nil,          # falls back to ENV["URLPIPE_API_KEY"]; raises Urlpipe::ConfigurationError if neither is set
  base_url: "https://urlpipe.dev",
  timeout: 90,           # seconds per HTTP request; the API holds a sync request up to 60 s
  max_retries: 2,        # see "Retries and idempotency"
  wait_timeout: 300,     # how long a long analysis is polled before Urlpipe::WaitTimeoutError
  poll_interval: 2       # seconds between polls of GET /result/:token
)
```

A client holds no connection state, so one instance can be shared across threads.

## Operations

Every method takes the URL first. These options work on all of them and are sent only when you give them:

| Option | What it does |
| --- | --- |
| `sync:` | `true` by default: the call returns the result. `false` returns straight away with a token (see [Async](#async-and-wait)). |
| `max_age:` | How fresh a cached result must be: seconds (`3600`) or a duration (`"3 days"`). `0` skips the cache. |
| `labels:` | Your own ids for the request, e.g. `{ client: "acme" }`. Returned with the result and the webhook. |
| `residential:` | `true` fetches the page from a home broadband address. |
| `report_to:` | A webhook URL the result is POSTed to (async calls). |
| `page_options:` | `wait_for_selector`, `delay`, `block_ads`, `block_cookie_banners`, `remove_selectors`. Not on `lighthouse`. |
| `idempotency_key:` | Sent as the `Idempotency-Key` header. |
| `extra:` | A Hash merged into the request body, for API options this version doesn't name yet. |

Option Hashes go to the API as given; it validates them and tells you what to change.

### markdown, html, summarize

`data` is a String.

```ruby
client.markdown("https://example.com", page_options: { block_cookie_banners: true }).data
client.html("https://example.com").data      # the rendered document
client.summarize("https://example.com").data # a Markdown summary
```

### screenshot

`data` is a `Urlpipe::Screenshot`: the decoded image bytes, its `mime_type` (`image/png`, `image/jpeg` or `image/webp`) and `result_url`, a link to the image that needs no API key.

```ruby
shot = client.screenshot("https://example.com",
                         screenshot_options: { viewport_width: 390, format: "webp" }).data
shot.save("example.webp")
shot.mime_type  # => "image/webp"
shot.result_url # => "https://..." - put it straight in an <img> tag
```

### meta

`data` is a Hash with `title`, `description`, `language`, `main_image_url`, `favicon_url`, `author_name`, `feed_url`, `publication_date` and `additional_author_information`. Any of them can be `nil`.

```ruby
client.meta("https://example.com").data["title"] # => "Example Domain"
```

### keywords

`data` is an Array of Strings, most relevant first.

```ruby
client.keywords("https://example.com").data # => ["example domain", "documentation", ...]
```

### console

`data` is an Array of `{"type" => "error" | "warning" | "exception", "text" => "..."}`.

```ruby
client.console("https://example.com").data.select { |entry| entry["type"] == "exception" }
```

### lighthouse

`data` is the audit as a Hash. `device:` is `"mobile"` (the default) or `"desktop"`; `include_audits: true` adds the full audits object.

```ruby
report = client.lighthouse("https://example.com", device: "desktop").data
report.dig("categories", "performance", "score")
```

### scrape

Several operations off one page visit, so you get them all much sooner. `data` is `{"url" => ..., "operations" => {"markdown" => {"success", "result", "error", "cached"}, ...}}`. Each operation succeeds or fails on its own. A screenshot inside a scrape stays Base64, as the API returns it.

```ruby
page = client.scrape("https://example.com", %w[markdown meta screenshot],
                     screenshot_options: { format: "jpeg" }).data
page.dig("operations", "meta", "result", "title")
```

## The Response

Every method returns a `Urlpipe::Response`:

| Field | |
| --- | --- |
| `status` | `"completed"`, `"accepted"` (an async request was accepted) or `"processing"` (still running). Also `completed?`, `accepted?`, `processing?`. |
| `data` | The result when completed, `nil` otherwise. |
| `token` | The request's result token. Fetching the result again with it is free for 30 days. |
| `labels` | The labels the request was made with; `{}` when it had none. |
| `meta` | `cache` (`"hit"`, `"miss"`, `"partial"`), `cache_age`, `processing_time_ms`, `quota` (`cost`, `limit`, `remaining`, `overage`, `resets_at`), `concurrency_limit`, `result_url`, `idempotent_replayed`. |

A value the API didn't send is `nil`; `idempotent_replayed` is always `true` or `false`. On an unlimited plan `quota.limit`, `quota.remaining` and `concurrency_limit` are the String `"unlimited"`.

## Long analyses

A sync request is held for up to 60 seconds. When an analysis takes longer (a Lighthouse audit, a slow site), the client polls `GET /result/:token` every 2 seconds and returns the result when it lands, so your code sees one call. After `wait_timeout` it raises `Urlpipe::WaitTimeoutError`, whose `token` you can collect later: the analysis keeps running.

## Async and wait

With `sync: false` the call returns at once with a token, and the work continues in the background. Collect it with `wait`, or with a webhook:

```ruby
accepted = client.lighthouse("https://example.com", sync: false)
accepted.status # => "accepted"

report = client.wait(accepted.token, operation: "lighthouse").data
```

`wait(token, operation: nil, timeout: wait_timeout, interval: poll_interval)` polls until the result is ready. `result(token, operation: nil)` checks once and returns a `"processing"` Response while it is still running.

The API doesn't say which operation produced a token, so pass `operation:` to get `data` typed the way that method returns it. Without it JSON comes back parsed and text stays a String, which means a screenshot stays Base64: `client.wait(token, operation: "screenshot")` decodes it into a `Urlpipe::Screenshot`.

## Webhooks

Turn on webhook signing for the project (Settings → Webhook Signing) and verify each delivery before trusting it. `Urlpipe::Webhook.verify` needs no client:

```ruby
# app/controllers/urlpipe_webhooks_controller.rb
class UrlpipeWebhooksController < ActionController::API
  def create
    payload = Urlpipe::Webhook.verify(request.raw_post, request.headers,
                                      ENV.fetch("URLPIPE_WEBHOOK_SECRET"))
    ProcessResultJob.perform_later(payload["token"])
    head :ok
  rescue Urlpipe::WebhookVerificationError
    head :unauthorized
  end
end
```

`verify(raw_body, headers, secret, tolerance: 300)` returns the payload Hash (`token`, `operation`, `labels`, `success`, `result`, `result_url`, `error`, `meta`), or raises `Urlpipe::WebhookVerificationError` saying why. It accepts any signature in the header that matches, so deliveries keep verifying through a secret rotation, and it refuses a timestamp more than `tolerance` seconds from now.

Pass the **raw** request body, exactly the bytes received: `request.raw_post` in Rails, `request.body.read` in Rack. Parsed and re-serialized JSON has different bytes and will not verify. `headers` can be Rails' `request.headers`, a Rack env or a plain Hash.

Make the handler idempotent on `token`: a delivery can be retried.

## Errors

Everything raised is a `Urlpipe::Error`, with `status`, `code` (the API's error code, when there is one), `message`, `body` (parsed JSON, or the raw text) and `token`.

| Error | When |
| --- | --- |
| `Urlpipe::AuthenticationError` | 401: the API key is missing or not an active project key. |
| `Urlpipe::EmailUnverifiedError` | 403: confirm the email address on the account. |
| `Urlpipe::InvalidRequestError` | 422 with a code: `invalid_url`, `invalid_max_age`, `invalid_options`, `invalid_labels`, `invalid_idempotency_key`, `idempotency_key_reused`, or a `report_to` the API won't deliver to. |
| `Urlpipe::AnalysisFailedError` | 422: the page couldn't be analysed; the message says why. A scrape where every operation failed keeps the scrape on `body`. |
| `Urlpipe::QuotaExceededError` | 429 on the Free plan: `limit`, `used`, `needed`, `resets_at`. |
| `Urlpipe::ConcurrencyLimitError` | 429: `limit` requests already `running`. |
| `Urlpipe::RateLimitedError` | 429: sending too fast; `retry_after` seconds. |
| `Urlpipe::NotFoundError` | 404: no result for this token in this project. |
| `Urlpipe::StaleResultError` | 410: the result is past the 30-day window. |
| `Urlpipe::ServerError` | Any other 5xx. |
| `Urlpipe::ConnectionError` | The API couldn't be reached, or a request outlived `timeout`. |
| `Urlpipe::WaitTimeoutError` | `wait_timeout` passed; `token` is still collectable. |
| `Urlpipe::ConfigurationError` | No API key. |
| `Urlpipe::WebhookVerificationError` | A webhook delivery didn't verify. |

```ruby
begin
  client.markdown(url)
rescue Urlpipe::AnalysisFailedError => e
  logger.info("Skipped #{url}: #{e.message}") # "The requested page was not found."
rescue Urlpipe::QuotaExceededError => e
  retry_at(e.resets_at)
end
```

## Retries and idempotency

The client retries, up to `max_retries` times, what a retry can fix: connection errors, 500/502/503, `rate_limited` (after `Retry-After`, capped at 60 s) and `concurrency_limit` (after 1 s, 2 s, ...). It never retries 401, 403, 404, 410, 422 or `quota_exceeded`.

Every analysis request that may be retried carries an `Idempotency-Key`: yours if you pass `idempotency_key:`, otherwise a fresh UUID for that call, reused on each of its retries. The API answers a repeated key with the first request's token and result, so a retry after a dropped connection never runs or bills the work twice. Pass your own key (a job id, say) to get the same guarantee across process restarts:

```ruby
client.markdown(url, idempotency_key: "import-#{job.id}")
```

Set `max_retries: 0` to turn retries off; no key is generated then.

## Links

- API docs: https://urlpipe.dev/docs
- Pricing: https://urlpipe.dev/pricing
- MCP server, to give an AI assistant the same tools: https://github.com/URLpipe/mcp

## Development

```sh
bundle install
bundle exec rake test
```

The tests run against a local stub server and never touch the network. Set `URLPIPE_API_KEY` to also run one live smoke test against the real API.

## License

MIT. Copyright (c) 2026 Aliat Partner S.L.
