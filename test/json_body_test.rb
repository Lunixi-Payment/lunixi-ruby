# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'

class JsonBodyTest < Minitest::Test
  def test_moves_only_javascript_array_index_keys_before_regular_keys
    input = { 'z' => 'Şükrü / 😀', '4294967295' => 1, '3' => 'c', '0' => 'zero', '02' => 2,
              '2' => { 'b' => true, '1' => nil }, 'a' => [1, 2] }
    assert_equal '{"0":"zero","2":{"1":null,"b":true},"3":"c","z":"Şükrü / 😀","4294967295":1,"02":2,"a":[1,2]}', Lunixi::JsonBody.dump(input)
  end

  def test_normalizes_symbols_and_rejects_duplicate_normalized_keys
    assert_equal '{"amount":1}', Lunixi::JsonBody.dump(amount: 1)
    assert_raises(Lunixi::ConfigurationError) { Lunixi::JsonBody.dump({ 'amount' => 1, amount: 2 }) }
  end

  def test_rejects_unsafe_integer_nonfinite_and_custom_objects
    [9_007_199_254_740_992, Float::NAN, Float::INFINITY, Object.new].each do |value|
      assert_raises(Lunixi::ConfigurationError) { Lunixi::JsonBody.dump(value) }
    end
    assert_raises(Lunixi::ConfigurationError) { Lunixi::JsonBody.dump("\xff".b.force_encoding('UTF-8')) }
    nested = 66.times.reduce(nil) { |value, _| [value] }
    assert_raises(Lunixi::ConfigurationError) { Lunixi::JsonBody.dump(nested) }
  end

  def test_floating_point_and_unicode_encoding_match_v8
    numbers = [0.0, -0.0, 1.0, 1e-7, 1e-6, 1e20, 1e21, -1e21, 1.2345678901234567, 5e-324, 2.2250738585072014e-308]
    input = { 'metadata' => { '4' => 'four', 'a' => "\u2028\u2029\b\n\"\\/" }, 'numbers' => numbers }
    actual = Lunixi::JsonBody.dump(input)
    script = 'let x="";process.stdin.on("data",d=>x+=d);' \
             'process.stdin.on("end",()=>process.stdout.write(JSON.stringify(JSON.parse(x))))'
    expected, status = Open3.capture2('node', '-e', script, stdin_data: JSON.generate(input))
    assert status.success?
    assert_equal expected, actual
  end
end
