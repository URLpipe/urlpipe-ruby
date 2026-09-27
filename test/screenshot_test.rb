# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class ScreenshotTest < UrlpipeTest
  PNG = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR".b
  JPEG = "\xFF\xD8\xFF\xE0\x00\x10JFIF".b
  WEBP = "RIFF\x1A\x00\x00\x00WEBPVP8X".b
  RESULT_URL = "https://urlpipe.dev/r/tok_123.png?sig=abc"

  def base64(bytes) = [bytes].pack("m")

  def test_decodes_base64_and_reads_result_url
    @server.respond(200, base64(PNG), QUOTA_HEADERS.merge("X-Result-Url" => RESULT_URL))

    response = client.screenshot("https://example.com", screenshot_options: { full_page: false })

    request = @server.last_request
    assert_equal "/screenshot", request.path
    assert_equal({ "url" => "https://example.com", "sync" => true, "screenshot_options" => { "full_page" => false } },
                 request.json)

    shot = response.data
    assert_instance_of Urlpipe::Screenshot, shot
    assert_equal PNG, shot.data
    assert_equal Encoding::BINARY, shot.data.encoding
    assert_equal "image/png", shot.mime_type
    assert_equal RESULT_URL, shot.result_url
    assert_equal RESULT_URL, response.meta.result_url
  end

  def test_detects_jpeg_and_webp
    @server.respond(200, base64(JPEG)).respond(200, base64(WEBP))

    assert_equal "image/jpeg", client.screenshot("https://example.com").data.mime_type
    assert_equal "image/webp", client.screenshot("https://example.com").data.mime_type
  end

  def test_unknown_bytes_fall_back_to_png
    @server.respond(200, base64("GIF89a".b))

    assert_equal "image/png", client.screenshot("https://example.com").data.mime_type
  end

  def test_save_writes_the_bytes
    @server.respond(200, base64(PNG))
    shot = client.screenshot("https://example.com").data

    Dir.mktmpdir do |dir|
      path = File.join(dir, "shot.png")
      assert_equal path, shot.save(path)
      assert_equal PNG, File.binread(path)
    end
  end

  def test_inspect_summarises_instead_of_dumping_bytes
    shot = Urlpipe::Screenshot.new(PNG, result_url: RESULT_URL)

    assert_equal "#<Urlpipe::Screenshot image/png #{PNG.bytesize} bytes result_url=#{RESULT_URL.inspect}>",
                 shot.inspect
  end
end
