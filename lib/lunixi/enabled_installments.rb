# frozen_string_literal: true

module Lunixi
  # enabledInstallments narrows the installment counts of one payment (intent, marketplace intent and
  # installment options): a nonempty list of distinct integers 1–36 that contains 1. Leaving the field
  # out means no restriction, so an empty list is refused (the gateway answers it with 400).
  module EnabledInstallments
    MIN = 1
    MAX = 36

    module_function

    # Returns a frozen copy in ascending order, the order the gateway expects.
    def check!(values, field = 'enabledInstallments')
      unless values.is_a?(Array) && !values.empty?
        raise ConfigurationError, "#{field} must be a nonempty array of installment counts; leave it out for no restriction, " \
                                  'or send [1] for a single payment only'
      end
      unless values.all? { |value| value.is_a?(Integer) && value.between?(MIN, MAX) }
        raise ConfigurationError, "#{field} values must be integers from #{MIN} to #{MAX}"
      end
      raise ConfigurationError, "#{field} lists an installment count more than once" unless values.uniq.size == values.size
      raise ConfigurationError, "#{field} must contain 1 (single payment)" unless values.include?(MIN)

      values.sort.freeze
    end
  end
end
