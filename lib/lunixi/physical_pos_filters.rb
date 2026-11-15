# frozen_string_literal: true

require 'date'

module Lunixi
  # Local checks of the physical POS list and report filters (PHYSICAL_POS_FILTERS).
  module PhysicalPosFilters
    AMOUNT_FILTERS = %w[amountFromMinor amountToMinor].freeze
    CALENDAR_DAY_FILTERS = %w[dateFrom dateTo].freeze

    module_function

    # Checks list / report filters of a route (PHYSICAL_POS_FILTERS) and returns the query. nil and ''
    # are left out. limit is 1–100; includeTotal a boolean; amountFromMinor / amountToMinor canonical
    # minor-unit strings; a Time in createdFrom / createdTo is sent as ISO 8601 UTC; dateFrom / dateTo
    # take a YYYY-MM-DD string, a Date or a Time (its own calendar day, not converted to
    # Europe/Istanbul). merchantReference and q are scanned for card numbers.
    def query!(filters, route)
      return {} if filters.nil?

      PhysicalPosRequest.reject_card_data!(filters, '(query)')
      allowed = PHYSICAL_POS_FILTERS.fetch(route)
      given = PhysicalPosRequest.wire_keys!(filters, allowed, 'physical POS', 'filter')
      allowed.each_with_object({}) do |key, query|
        next unless given.key?(key)

        value = given[key]
        next query[key] = PhysicalPosRequest.money!(value, key) if AMOUNT_FILTERS.include?(key)
        next if value.nil? || value == ''

        query[key] = filter_value(key, value)
        free_text = PHYSICAL_POS_FREE_TEXT_FILTERS.include?(key)
        raise PhysicalPosRequest.card_data_rejected(key) if free_text && PhysicalPosCardData.contains_pan_like_value?(query[key])
      end
    end

    def filter_value(key, value)
      case key
      when 'limit'
        unless value.is_a?(Integer) && value.between?(1, PHYSICAL_POS_MAX_LIMIT)
          raise ConfigurationError, "'limit' must be an integer between 1 and #{PHYSICAL_POS_MAX_LIMIT}."
        end

        value.to_s
      when 'includeTotal' then PhysicalPosRequest.boolean!(value, key) ? 'true' : 'false'
      else time_filter(key, value)
      end
    end

    def time_filter(key, value)
      return value.strftime('%Y-%m-%d') if CALENDAR_DAY_FILTERS.include?(key) && (value.is_a?(Time) || value.is_a?(Date))
      return value.getutc.strftime('%Y-%m-%dT%H:%M:%S.%LZ') if value.is_a?(Time)
      raise ConfigurationError, "'#{key}' must be a string." unless value.is_a?(String)

      value
    end
  end
end
