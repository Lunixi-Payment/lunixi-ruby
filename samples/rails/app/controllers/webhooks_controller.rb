# frozen_string_literal: true

# External gateway callback: no cookie session and no CSRF bypass on buyer routes.
class WebhooksController < ActionController::API
  def create
    headers = %w[x-lunixi-event-id x-lunixi-event-type x-lunixi-signature-timestamp x-lunixi-signature].to_h do |name|
      [name, request.headers[name]]
    end.compact
    WebhookProcessor.new.call(request.raw_post, headers)
    head :ok
  rescue Lunixi::WebhookError
    head :bad_request
  rescue Lunixi::Error, ActiveRecord::ActiveRecordError, KeyError
    # Receipt/order changes roll back. Gateway retries or an operator reconciles.
    head :service_unavailable
  end
end
