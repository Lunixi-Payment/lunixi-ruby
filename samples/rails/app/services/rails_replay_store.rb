# frozen_string_literal: true

# The unique receipt and the order change commit in the SAME database transaction.
# Handler failure rolls the receipt back so gateway redelivery can recover.
class RailsReplayStore
  def initialize(connection_id: 'primary')
    @connection_id = connection_id
  end

  def process_once(id:, digest:)
    ActiveRecord::Base.transaction(requires_new: true) do
      LunixiReceipt.create!(connection_id: @connection_id, event_id: id, body_digest: digest)
      yield
    end
    :processed
  rescue ActiveRecord::RecordNotUnique
    receipt = LunixiReceipt.find_by!(connection_id: @connection_id, event_id: id)
    raise Lunixi::ReplayConflict, 'Event id was reused with a different body' unless OpenSSL.fixed_length_secure_compare(receipt.body_digest, digest)

    :duplicate
  end
end
