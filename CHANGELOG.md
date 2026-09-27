# Changelog

## 0.1.1

- The gem's author is listed as URLpipe.

## 0.1.0

The first release.

- `Urlpipe::Client` with one method per operation: `markdown`, `html`, `summarize`, `screenshot`, `meta`, `keywords`, `console`, `lighthouse` and `scrape`, plus `result` and `wait` for tokens.
- Calls are synchronous by default. An analysis that outlives the API's 60-second sync window is polled until it lands.
- `Urlpipe::Response` with the result typed per operation, the token, labels and the parsed metadata headers.
- Screenshots decoded to bytes, with the MIME type and the key-free `result_url`.
- Automatic retries with an `Idempotency-Key` per call, so a retry never runs or bills the work twice.
- A typed error for every documented API error.
- `Urlpipe::Webhook.verify` for signed webhook deliveries.
