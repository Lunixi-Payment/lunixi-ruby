# frozen_string_literal: true

require 'openssl'
require 'base64'
require 'digest'

module Lunixi
  # Uses OpenSSL's Ed25519 implementation; no curve arithmetic is implemented here.
  class Signer
    PREFIX = ['302e020100300506032b657004220420'].pack('H*').freeze

    def initialize(private_key)
      raise ConfigurationError, 'An Ed25519 private key is required' unless private_key.is_a?(String) && !private_key.strip.empty?

      material = private_key.strip
      unless material.include?('-----BEGIN')
        raw = Base64.strict_decode64(material)
        raw = PREFIX + raw[0, 32] if [32, 64].include?(raw.bytesize)
        material = raw
      end
      @key = OpenSSL::PKey.read(material)
      raise ConfigurationError, 'Only Ed25519 private keys are accepted' unless @key.oid == 'ED25519'

      @key.sign(nil, 'key-check') # Reject public-only keys at construction time.
    rescue OpenSSL::OpenSSLError, ArgumentError
      raise ConfigurationError, 'Invalid Ed25519 private key', cause: nil
    end

    def sign(message)
      Base64.strict_encode64(@key.sign(nil, message))
    rescue OpenSSL::OpenSSLError
      raise SignatureError, 'Ed25519 signing failed', cause: nil
    end

    def self.canonical(method, path, date, nonce, digest = nil)
      lines = [method.upcase, path, "X-Date:#{date}", "X-Nonce:#{nonce}"]
      lines << "Digest:#{digest}" if digest
      lines.join("\n")
    end

    def self.digest(body)
      "SHA-256=#{Base64.strict_encode64(Digest::SHA256.digest(body))}"
    end

    def inspect
      '#<Lunixi::Signer [REDACTED]>'
    end
  end
end
