# frozen_string_literal: true

class AddCheckoutPresentation < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :checkout_mode, :string
    add_column :orders, :checkout_request, :text
    add_column :orders, :checkout_started_at, :datetime
    add_column :orders, :payment_page_url, :text
    add_column :orders, :checkout_legacy, :boolean, null: false, default: false
    reversible do |direction|
      direction.up do
        # Before this migration every checkout used hosted-origin credentials.
        # Old unknown requests/URLs cannot be reconstructed or reset safely.
        execute "UPDATE orders SET checkout_mode='hosted', checkout_legacy=1"
      end
    end
  end
end
