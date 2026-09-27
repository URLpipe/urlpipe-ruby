# frozen_string_literal: true

require_relative "urlpipe/version"
require_relative "urlpipe/errors"
require_relative "urlpipe/response"
require_relative "urlpipe/screenshot"
require_relative "urlpipe/client"
require_relative "urlpipe/webhook"

# Ruby client for the URLpipe API (https://urlpipe.dev): turn a URL into
# Markdown, rendered HTML, a screenshot, metadata, a summary, keywords,
# console errors or a Lighthouse audit.
#
#   client = Urlpipe::Client.new # reads URLPIPE_API_KEY
#   client.markdown("https://example.com").data
module Urlpipe
end
