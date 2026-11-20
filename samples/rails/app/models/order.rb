# frozen_string_literal: true

# This runnable sample represents one merchant and fixed-total TRY orders.
class Order < ApplicationRecord
  ORDER_DETAIL_FIELDS = %w[buyer billingAddress shippingAddress basketItems].freeze

  encrypts :checkout_token, :payment_page_url, :checkout_request, :order_details
  before_validation :assign_identifiers, on: :create
  validates :public_id, :checkout_key, presence: true, uniqueness: true
  validates :amount_minor, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: Lunixi::Money::MAX }
  validates :currency, inclusion: { in: ['TRY'] }
  validates :status, inclusion: { in: %w[pending paid review] }

  # The stored buyer, addresses and basket ({} when none are stored); the SDK refuses an incomplete set.
  def order_details_payload
    return {} if order_details.blank?

    details = JSON.parse(order_details)
    details.is_a?(Hash) ? details.slice(*ORDER_DETAIL_FIELDS) : {}
  end

  private

  def assign_identifiers
    self.public_id ||= SecureRandom.uuid
    self.checkout_key ||= SecureRandom.uuid
  end
end
