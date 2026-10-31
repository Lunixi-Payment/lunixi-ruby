# frozen_string_literal: true

# This runnable sample represents one merchant and fixed-total TRY orders.
class Order < ApplicationRecord
  encrypts :checkout_token
  before_validation :assign_identifiers, on: :create
  validates :public_id, :checkout_key, presence: true, uniqueness: true
  validates :amount_minor, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: Lunixi::JsonBody::MAX_SAFE_INTEGER }
  validates :currency, inclusion: { in: ['TRY'] }
  validates :status, inclusion: { in: %w[pending paid review] }

  private

  def assign_identifiers
    self.public_id ||= SecureRandom.uuid
    self.checkout_key ||= SecureRandom.uuid
  end
end
