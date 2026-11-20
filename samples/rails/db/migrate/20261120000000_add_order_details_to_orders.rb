# frozen_string_literal: true

# Order details every payment requires (buyer, billing/shipping address, basket), stored with the order
# as encrypted JSON. They are sent with the intent but are not part of the reserved checkout request.
class AddOrderDetailsToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :order_details, :text
  end
end
