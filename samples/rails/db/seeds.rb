# frozen_string_literal: true

# Synthetic buyer, address and basket of the demo order; a real store takes them from its checkout.
address = { contactName: 'Demo Buyer', address: 'Example Street 1', city: 'Istanbul', country: 'Turkey', zipCode: '34000' }
order_details = {
  buyer: { name: 'Demo', surname: 'Buyer', identityNumber: '11111111111', email: 'buyer@example.com', gsmNumber: '+905350000000',
           city: 'Istanbul', country: 'Turkey', zipCode: '34000' },
  billingAddress: address,
  basketItems: [{ id: 'demo-1', name: 'Demo service', category1: 'Services', itemType: 'VIRTUAL', price: '10050' }]
}

Order.find_or_create_by!(public_id: '00000000-0000-4000-8000-000000000001') do |order|
  order.amount_minor = 10_050
  order.currency = 'TRY'
  order.order_details = JSON.generate(order_details)
end
