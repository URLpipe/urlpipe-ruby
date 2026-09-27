# frozen_string_literal: true

require_relative "lib/urlpipe/version"

Gem::Specification.new do |spec|
  spec.name = "urlpipe"
  spec.version = Urlpipe::VERSION
  spec.authors = ["URLpipe"]
  spec.email = ["contact@urlpipe.dev"]

  spec.summary = "Ruby client for the URLpipe API: turn a URL into Markdown, HTML, a screenshot and more."
  spec.description = "Official Ruby client for URLpipe. Get a page's Markdown, rendered HTML, a full-page " \
                     "screenshot, metadata, a summary, keywords, console errors or a Lighthouse audit, " \
                     "rendered in real Chrome. Handles long analyses, retries with idempotency keys, and " \
                     "webhook signature verification. No runtime dependencies."
  spec.homepage = "https://urlpipe.dev"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "documentation_uri" => "https://urlpipe.dev/docs",
    "source_code_uri" => "https://github.com/URLpipe/urlpipe-ruby",
    "changelog_uri" => "https://github.com/URLpipe/urlpipe-ruby/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/URLpipe/urlpipe-ruby/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]
end
