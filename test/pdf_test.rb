# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class PdfTest < UrlpipeTest
  PDF = "%PDF-1.4\n\x00\x01\x02%%EOF".b
  RESULT_URL = "https://urlpipe.dev/r/tok_123.pdf?sig=abc"

  def base64(bytes) = [bytes].pack("m")

  def test_decodes_base64_and_reads_result_url
    @server.respond(200, base64(PDF), QUOTA_HEADERS.merge("X-Result-Url" => RESULT_URL))

    response = client.pdf("https://example.com", pdf_options: { paper_size: "letter" })

    request = @server.last_request
    assert_equal "/pdf", request.path
    assert_equal({ "url" => "https://example.com", "sync" => true, "pdf_options" => { "paper_size" => "letter" } },
                 request.json)

    pdf = response.data
    assert_instance_of Urlpipe::Pdf, pdf
    assert_equal PDF, pdf.data
    assert_equal Encoding::BINARY, pdf.data.encoding
    assert_equal "application/pdf", pdf.mime_type
    assert_equal RESULT_URL, pdf.result_url
    assert_equal RESULT_URL, response.meta.result_url
  end

  def test_result_with_the_pdf_hint_decodes
    @server.respond(200, base64(PDF))

    assert_equal PDF, client.result("tok_123", operation: "pdf").data.data
  end

  def test_save_writes_the_bytes
    @server.respond(200, base64(PDF))
    pdf = client.pdf("https://example.com").data

    Dir.mktmpdir do |dir|
      path = File.join(dir, "page.pdf")
      assert_equal path, pdf.save(path)
      assert_equal PDF, File.binread(path)
    end
  end

  def test_inspect_summarises_instead_of_dumping_bytes
    pdf = Urlpipe::Pdf.new(PDF, result_url: RESULT_URL)

    assert_equal "#<Urlpipe::Pdf #{PDF.bytesize} bytes result_url=#{RESULT_URL.inspect}>", pdf.inspect
  end
end
