# frozen_string_literal: true

require 'tempfile'
require 'socket'

class LocalTlsServer
  attr_reader :port, :ca_path, :requests

  def initialize(&handler)
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse('/CN=localhost')
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    factory = OpenSSL::X509::ExtensionFactory.new
    factory.subject_certificate = cert
    factory.issuer_certificate = cert
    cert.add_extension(factory.create_extension('basicConstraints', 'CA:TRUE', true))
    cert.add_extension(factory.create_extension('subjectAltName', 'DNS:localhost'))
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    @ca = Tempfile.new(['lunixi-test-ca', '.pem'])
    @ca.write(cert.to_pem)
    @ca.flush
    @ca_path = @ca.path
    @tcp = TCPServer.new('127.0.0.1', 0)
    @port = @tcp.addr[1]
    context = OpenSSL::SSL::SSLContext.new
    context.cert = cert
    context.key = key
    @server = OpenSSL::SSL::SSLServer.new(@tcp, context)
    @requests = []
    @thread = Thread.new do
      serve(handler)
    rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
      # Expected when a peer rejects the synthetic CA or a bounded reader exits.
    end
    @thread.report_on_exception = false
  end

  def close
    @tcp.close
    @thread.join(1) || @thread.kill
    @ca.close!
  end

  private

  def serve(handler)
    socket = @server.accept
    line = socket.gets
    return unless line

    headers = {}
    while (header = socket.gets) && header != "\r\n"
      name, value = header.split(':', 2)
      headers[name.downcase] = value.strip
    end
    body = socket.read(headers.fetch('content-length', '0').to_i)
    @requests << { line: line, headers: headers, body: body }
    status, result_headers, result_body = handler.call
    socket.write("HTTP/1.1 #{status} Test\r\nConnection: close\r\nContent-Length: #{result_body.bytesize}\r\n")
    result_headers.each { |name, value| socket.write("#{name}: #{value}\r\n") }
    socket.write("\r\n#{result_body}")
  ensure
    socket&.close
  end
end
