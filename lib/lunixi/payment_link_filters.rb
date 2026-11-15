# frozen_string_literal: true

require 'time'

module Lunixi
  # Local checks of the payment-link list filters (links, attempts and payments of a link).
  module PaymentLinkFilters
    LINK_LIST_FILTERS = %w[limit cursor includeTotal state usage amountMode environment tag branchCode createdById query
                           createdFrom createdTo].freeze
    ATTEMPT_LIST_FILTERS = %w[limit cursor includeTotal state].freeze
    PAYMENT_LIST_FILTERS = %w[limit cursor includeTotal].freeze

    module_function

    # Lists accept an Array for state, usage and amountMode (sent as a comma list) and a Time for the
    # createdFrom / createdTo window.
    def list_query!(filters, allowed, operation)
      data = filters.transform_keys(&:to_s)
      unknown = data.keys - allowed
      raise ConfigurationError, "#{operation} does not take #{unknown.join(', ')}; filters: #{allowed.join(', ')}" unless unknown.empty?

      allowed.each_with_object({}) do |key, query|
        value = data[key]
        next if value.nil? || value == ''

        value = value.join(',') if value.is_a?(Array)
        value = value.getutc.iso8601(3) if value.is_a?(Time)
        query[key] = value unless value == ''
      end
    end
  end
end
