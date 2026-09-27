# frozen_string_literal: true

module Urlpipe
  # A decoded screenshot: +data+ is the image as a binary String,
  # +mime_type+ is "image/png", "image/jpeg" or "image/webp", and
  # +result_url+ is a link to the same image that needs no API key.
  class Screenshot
    attr_reader :data, :mime_type, :result_url

    # Builds a Screenshot from the API's Base64 body.
    def self.from_base64(text, result_url: nil)
      new(text.to_s.unpack1("m"), result_url: result_url)
    end

    def self.detect_mime_type(bytes)
      if bytes.start_with?("\x89PNG\r\n\x1A\n".b)
        "image/png"
      elsif bytes.start_with?("\xFF\xD8\xFF".b)
        "image/jpeg"
      elsif bytes.byteslice(0, 4) == "RIFF".b && bytes.byteslice(8, 4) == "WEBP".b
        "image/webp"
      else
        "image/png"
      end
    end

    def initialize(data, result_url: nil, mime_type: nil)
      @data = data.b
      @mime_type = mime_type || self.class.detect_mime_type(@data)
      @result_url = result_url
    end

    # Writes the image to +path+ and returns the path.
    def save(path)
      File.binwrite(path, data)
      path
    end

    def bytesize = data.bytesize

    def inspect
      "#<#{self.class.name} #{mime_type} #{bytesize} bytes result_url=#{result_url.inspect}>"
    end
  end
end
