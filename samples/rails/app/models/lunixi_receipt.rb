# frozen_string_literal: true

class LunixiReceipt < ApplicationRecord
  validates :connection_id, :event_id, :body_digest, presence: true
end
