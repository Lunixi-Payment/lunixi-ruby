# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'
require 'socket'

require_relative 'local_tls_server'

class TransportTest < Minitest::Test
  def test_sends_exact_utf8_body_over_verified_tls
    server = LocalTlsServer.new { [200, { 'X-Request-Id' => 'req_tls' }, '{"data":{"ok":true}}'] }
    transport = Lunixi::NetHttpTransport.new(timeout: 1, ca_file: server.ca_path)
    body = Lunixi::JsonBody.dump({ 'name' => 'Şükrü / 雪' })
    result = transport.call(method: 'POST', uri: URI("https://localhost:#{server.port}/api/v1/test?q=a%20b"),
                            headers: { 'Content-Type' => 'application/json' }, body: body)
    assert_equal 200, result.status
    assert_equal 'req_tls', result.headers['x-request-id']
    assert_equal "POST /api/v1/test?q=a%20b HTTP/1.1\r\n", server.requests.first[:line]
    assert_equal body.b, server.requests.first[:body].b
  ensure
    server&.close
  end

  def test_rejects_untrusted_server_certificate
    server = LocalTlsServer.new { [200, {}, '{}'] }
    assert_raises(Lunixi::TransportError) do
      Lunixi::NetHttpTransport.new(timeout: 1).call(method: 'GET', uri: URI("https://localhost:#{server.port}/api/v1/test"), headers: {}, body: nil)
    end
    assert_empty server.requests
  ensure
    server&.close
  end

  def test_rejects_trusted_certificate_for_wrong_hostname
    server = LocalTlsServer.new { [200, {}, '{}'] }
    assert_raises(Lunixi::TransportError) do
      Lunixi::NetHttpTransport.new(timeout: 1, ca_file: server.ca_path).call(
        method: 'GET', uri: URI("https://127.0.0.1:#{server.port}/api/v1/test"), headers: {}, body: nil
      )
    end
    assert_empty server.requests
  ensure
    server&.close
  end

  def test_redirect_is_returned_without_following_it
    server = LocalTlsServer.new { [302, { 'Location' => 'https://attacker.example/collect' }, '{}'] }
    result = Lunixi::NetHttpTransport.new(timeout: 1, ca_file: server.ca_path).call(
      method: 'GET', uri: URI("https://localhost:#{server.port}/api/v1/test"), headers: { 'Authorization' => 'Bearer synthetic' }, body: nil
    )
    assert_equal 302, result.status
    assert_equal 1, server.requests.size
  ensure
    server&.close
  end

  def test_response_size_is_bounded_while_reading
    server = LocalTlsServer.new { [200, {}, 'x' * (Lunixi::NetHttpTransport::MAX_RESPONSE_BYTES + 1)] }
    assert_raises(Lunixi::TransportError) do
      Lunixi::NetHttpTransport.new(timeout: 1, ca_file: server.ca_path).call(
        method: 'GET', uri: URI("https://localhost:#{server.port}/api/v1/test"), headers: {}, body: nil
      )
    end
  ensure
    server&.close
  end
end
