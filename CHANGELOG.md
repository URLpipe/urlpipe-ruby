# Changelog

## Unreleased

- `pdf` returns the whole rendered page as a PDF (`POST /pdf`): a `Urlpipe::Pdf` with the decoded bytes, `mime_type`, `result_url` and `save`. `pdf_options:` choose the paper, orientation, margins, scale, backgrounds, the print or screen stylesheet and `single_page`.
- `extract` returns data from a page in a schema you define (`POST /extract`): pass `fields` and get a Hash with exactly those keys, in order, `nil` where the page gives no value. `instructions:` adds guidance in plain words.
- `scrape` takes `pdf_options:`, `fields:` and `instructions:` for its `pdf` and `extract` operations.
- `user_agent:` on `Urlpipe::Client.new` names the program making the requests; the User-Agent then reads `<product> urlpipe-ruby/<version>`.
- `technologies` detects what a page is built with (`POST /technologies`): its CMS, frameworks, analytics, CDN and web server, each with its version, a confidence and the signals it was detected by.
- `Meta#final_url` is the address the page ended on, after its redirects (the `X-Final-Url` header). A `/meta` result, a `/scrape` result and a webhook payload carry it as `"final_url"` too.
- `meta` returns the fixed shape of `/meta`: every key always present — `canonical_url`, `title`, `description`, `site_name`, `type`, `language`, `locale`, `authors`, `published_at`, `modified_at`, `image`, `video`, `favicon_url`, `icons`, `logo_url`, `feeds`, `keywords`, `theme_color`, `generator`, `manifest_url`, `robots`, `open_graph`, `twitter`, `alternates`, `oembed_url`, `structured_data_types`. `main_image_url`, `author_name`, `publication_date`, `feed_url` and `additional_author_information` are gone: read `image["url"]`, `authors`, `published_at` and `feeds`.

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
