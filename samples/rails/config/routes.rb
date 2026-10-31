# frozen_string_literal: true

Rails.application.routes.draw do
  get '/orders/:public_id', to: 'orders#show', as: :order
  post '/orders/:public_id/checkout', to: 'orders#checkout', as: :checkout_order
  get '/orders/:public_id/return', to: 'orders#return_from_payment', as: :return_order
  post '/webhooks/lunixi', to: 'webhooks#create'
end
