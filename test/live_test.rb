# frozen_string_literal: true

require_relative "test_helper"

# Runs against the real API only when URLPIPE_API_KEY is set. It spends at
# most one credit (nothing when the result is cached).
class LiveTest < Minitest::Test
  def test_markdown_of_example_com
    skip "set URLPIPE_API_KEY to run the live smoke test" if ENV["URLPIPE_API_KEY"].to_s.empty?

    response = Urlpipe::Client.new.markdown("https://example.com")

    assert_predicate response, :completed?
    assert_match(/Example Domain/, response.data)
    refute_nil response.token
  end
end
