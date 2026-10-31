# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'openssl'

module Lunixi
  Response = Struct.new(:status, :headers, :body, keyword_init: true)

  # Net::HTTP never follows redirects. Each call gets a separate connection,
  # avoiding sharing mutable Net::HTTP state between application threads.
  class NetHttpTransport
    MAX_RESPONSE_BYTES = 8 * 1024 * 1024

    def initialize(timeout: 30, ca_file: nil)
      @timeout = timeout
      @ca_file = ca_file
    end

    def call(method:, uri:, headers:, body:)
      http = Net::HTTP.new(uri.host, uri.port, nil) # Do not inherit proxy credentials/environment.
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.min_version = OpenSSL::SSL::TLS1_2_VERSION
      http.ca_file = @ca_file if @ca_file
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http.write_timeout = @timeout
      http.max_retries = 0 # Retry policy belongs to Client, never Net::HTTP.
      request = Net::HTTPGenericRequest.new(method, !body.nil?, method != 'HEAD', uri.request_uri, headers)
      request.body = body unless body.nil?
      data = +''
      result = nil
      http.start do |session|
        session.request(request) do |response|
          response.read_body do |chunk|
            data << chunk
            raise TransportError, 'Gateway response exceeds the size limit' if data.bytesize > MAX_RESPONSE_BYTES
          end
          result = Response.new(status: response.code.to_i, headers: response.each_header.to_h, body: data)
        end
      end
      result
    rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError
      raise TransportError, 'Gateway connection failed; reconcile an uncertain payment before retrying', cause: nil
    end
  end
end
