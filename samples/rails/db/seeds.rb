# frozen_string_literal: true

Order.find_or_create_by!(public_id: '00000000-0000-4000-8000-000000000001') do |order|
  order.amount_minor = 10_050
  order.currency = 'TRY'
end
