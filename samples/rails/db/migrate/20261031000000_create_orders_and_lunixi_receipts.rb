# frozen_string_literal: true

class CreateOrdersAndLunixiReceipts < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |table|
      table.string :public_id, null: false
      table.bigint :amount_minor, null: false
      table.string :currency, null: false, default: 'TRY'
      table.string :status, null: false, default: 'pending'
      table.string :checkout_key, null: false
      table.string :intent_id
      table.text :checkout_token
      table.timestamps
    end
    add_index :orders, :public_id, unique: true
    add_index :orders, :checkout_key, unique: true
    add_index :orders, :intent_id, unique: true
    add_check_constraint :orders, 'amount_minor > 0', name: 'positive_order_amount'

    create_table :lunixi_receipts do |table|
      table.string :connection_id, null: false
      table.string :event_id, null: false
      table.string :body_digest, null: false
      table.timestamps
    end
    add_index :lunixi_receipts, %i[connection_id event_id], unique: true
  end
end
