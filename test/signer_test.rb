# frozen_string_literal: true

require_relative 'test_helper'

class SignerTest < Minitest::Test
  def test_rfc8032_ed25519_vector
    # Public RFC 8032 section 7.1 test vector, never a merchant credential.
    seed = ['9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60'].pack('H*')
    signer = Lunixi::Signer.new(Base64.strict_encode64(seed))
    expected = 'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b'
    assert_equal expected, Base64.strict_decode64(signer.sign('')).unpack1('H*')
  end

  def test_canonical_request_uses_exact_signed_path_and_headers
    body = Lunixi::JsonBody.dump(amount: 10_050, currency: 'TRY')
    digest = Lunixi::Signer.digest(body)
    canonical = Lunixi::Signer.canonical('post', '/api/v1/payments/intents', '2026-10-31T12:00:00Z', 'nonce', digest)
    assert_equal ['POST', '/api/v1/payments/intents', 'X-Date:2026-10-31T12:00:00Z', 'X-Nonce:nonce', "Digest:#{digest}"].join("\n"), canonical
    signature = Lunixi::Signer.new(TEST_KEY.private_to_pem).sign(canonical)
    assert TEST_KEY.verify(nil, Base64.strict_decode64(signature), canonical)
    refute TEST_KEY.verify(nil, Base64.strict_decode64(signature), "#{canonical}changed")
  end

  def test_rejects_non_ed25519_and_public_only_material_without_leaking_input
    [OpenSSL::PKey::RSA.generate(2048).private_to_pem, TEST_KEY.public_to_pem, 'PRIVATE_SECRET_BAD_KEY'].each do |material|
      error = assert_raises(Lunixi::ConfigurationError) { Lunixi::Signer.new(material) }
      refute_includes error.full_message, material
    end
    refute_includes Lunixi::Signer.new(TEST_KEY.private_to_pem).inspect, TEST_KEY.private_to_pem
  end
end
