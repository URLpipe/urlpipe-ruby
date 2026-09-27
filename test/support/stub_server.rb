# frozen_string_literal: true

require "json"
require "socket"

# A tiny HTTP/1.1 server on 127.0.0.1 that answers with the responses queued
# on it, in order, and records every request it receives. One connection per
# request (Connection: close), which is how the client talks anyway.
class StubServer
  Request = Struct.new(:method, :path, :headers, :body, keyword_init: true) do
    def json = JSON.parse(body)
    def [](name) = headers[name.downcase]
  end

  REASONS = {
    200 => "OK", 202 => "Accepted", 401 => "Unauthorized", 403 => "Forbidden",
    404 => "Not Found", 410 => "Gone", 422 => "Unprocessable Entity",
    429 => "Too Many Requests", 500 => "Internal Server Error", 502 => "Bad Gateway",
    503 => "Service Unavailable", 504 => "Gateway Timeout"
  }.freeze

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @queue = []
    @requests = []
    @mutex = Mutex.new
    @thread = Thread.new { serve }
  end

  def url = "http://127.0.0.1:#{@server.addr[1]}"

  def requests = @mutex.synchronize { @requests.dup }

  def last_request = requests.last

  # Queues one response. A Hash or Array body is sent as JSON.
  def respond(status, body = "", headers = {})
    if body.is_a?(Hash) || body.is_a?(Array)
      headers = { "Content-Type" => "application/json; charset=utf-8" }.merge(headers)
      body = JSON.generate(body)
    else
      headers = { "Content-Type" => "text/plain; charset=utf-8" }.merge(headers)
    end
    @mutex.synchronize { @queue << [status, headers, body] }
    self
  end

  # Queues a dropped connection: the request is read and the socket closed
  # without an answer.
  def drop
    @mutex.synchronize { @queue << :drop }
    self
  end

  def shutdown
    @thread.kill
    @server.close
  end

  private

  def serve
    loop do
      socket = @server.accept
      handle(socket)
    rescue IOError, SystemCallError
      next
    ensure
      socket&.close unless socket&.closed?
    end
  end

  def handle(socket)
    request_line = socket.gets or return
    method, path, = request_line.split(" ")
    headers = {}
    while (line = socket.gets) && line != "\r\n"
      name, value = line.split(":", 2)
      headers[name.strip.downcase] = value.strip
    end
    body = socket.read(headers["content-length"].to_i).to_s

    @mutex.synchronize { @requests << Request.new(method:, path:, headers:, body:) }
    reply = @mutex.synchronize { @queue.shift } || [500, { "Content-Type" => "text/plain" }, "no stubbed response"]
    return if reply == :drop

    status, response_headers, response_body = reply
    response_body = response_body.b
    out = +"HTTP/1.1 #{status} #{REASONS.fetch(status, "Status")}\r\n"
    response_headers.merge("Content-Length" => response_body.bytesize.to_s, "Connection" => "close")
                    .each { |name, value| out << "#{name}: #{value}\r\n" }
    out << "\r\n"
    socket.write(out.b + response_body)
  end
end
