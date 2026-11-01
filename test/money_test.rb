# frozen_string_literal: true
require_relative 'test_helper'

class MoneyTest < Minitest::Test
  def test_canonical_strings_and_large_exactness
    large = '9007199254740993'
    assert_equal large, Lunixi::Money.minor(large)
    assert_equal '-9007199254740993', Lunixi::Money.minor('-9007199254740993', signed: true)
    [1, 1.5, '0', '-0', '01', '+1', ' 1', '1.0', '1e3', '9223372036854775808'].each do |value|
      assert_raises(Lunixi::ConfigurationError) { Lunixi::Money.minor(value) }
    end
    [[large, 'JPY'], ['90071992547409.93', 'TRY'], ['9007199254740.993', 'KWD']].each do |decimal, currency|
      assert_equal large, Lunixi::Money.decimal_to_minor(decimal, currency)
    end
    assert_raises(Lunixi::ConfigurationError) { Lunixi::Money.decimal_to_minor('1.1', 'JPY') }
    assert_raises(Lunixi::ConfigurationError) { Lunixi::Money.decimal_to_minor('1', 'ZZZ') }
    assert_raises(Lunixi::ConfigurationError) { Lunixi::Money.validate_fields({ 'data' => { 'amount' => 1 } }, response: true) }
    assert Lunixi::Money.validate_fields({ 'metadata' => { 'amount' => 1 }, 'providerPayload' => { 'amount' => 1 }, 'rate' => 1.5 })
  end
end
