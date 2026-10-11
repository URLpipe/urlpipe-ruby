# frozen_string_literal: true

module Urlpipe
  # A decoded PDF of the page: +data+ is the PDF as a binary String,
  # +mime_type+ is "application/pdf", and +result_url+ is a link to the same
  # PDF that needs no API key.
  class Pdf
    MIME_TYPE = "application/pdf"

    attr_reader :data, :result_url

    # Builds a Pdf from the API's Base64 body.
    def self.from_base64(text, result_url: nil)
      new(text.to_s.unpack1("m"), result_url: result_url)
    end

    def initialize(data, result_url: nil)
      @data = data.b
      @result_url = result_url
    end

    def mime_type = MIME_TYPE

    # Writes the PDF to +path+ and returns the path.
    def save(path)
      File.binwrite(path, data)
      path
    end

    def bytesize = data.bytesize

    def inspect
      "#<#{self.class.name} #{bytesize} bytes result_url=#{result_url.inspect}>"
    end
  end
end
