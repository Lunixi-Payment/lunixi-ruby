# frozen_string_literal: true

require 'date'

module Lunixi
  # Most rows of a promissory-note schedule (and most notes of a payment).
  PROMISSORY_NOTE_MAX_SCHEDULE_ITEMS = 24

  # Status of one note (notes[].status).
  module PromissoryNoteStatus
    ISSUED = 'ISSUED'
    PAID = 'PAID'
    PROTESTED = 'PROTESTED'
    CANCELLED = 'CANCELLED'

    ALL = [ISSUED, PAID, PROTESTED, CANCELLED].freeze
  end

  # Document type of the issued notes, from your provider connection settings.
  module PromissoryNoteDocumentType
    PROMISSORY_NOTE = 'PROMISSORY_NOTE'
    PAYMENT_ORDER = 'PAYMENT_ORDER'

    ALL = [PROMISSORY_NOTE, PAYMENT_ORDER].freeze
  end

  # Per-note result of payments.cancel_promissory_notes (cancelResults[].result).
  module PromissoryNoteCancelResult
    CANCELLED = 'CANCELLED'
    # The note was already cancelled.
    ALREADY_CLOSED = 'ALREADY_CLOSED'
    # The note was collected or protested; it cannot be cancelled.
    NOT_CANCELLABLE = 'NOT_CANCELLABLE'
    # The note was not cancelled; errorCode tells whether to try again.
    FAILED = 'FAILED'

    ALL = [CANCELLED, ALREADY_CLOSED, NOT_CANCELLABLE, FAILED].freeze
  end

  # cancelResults[].errorCode: a Lunixi code; nil for CANCELLED and ALREADY_CLOSED.
  module PromissoryNoteCancelErrorCode
    # The note was collected or cannot be cancelled (NOT_CANCELLABLE).
    NOT_CANCELLABLE = 'payment.promissory_note.not_cancellable'
    # Temporary: the provider could not be reached; cancel again later (FAILED).
    PROVIDER_UNAVAILABLE = 'payment.promissory_note.provider_unavailable'
    # Permanent: the cancellation was refused (FAILED).
    CANCEL_REJECTED = 'payment.promissory_note.cancel_rejected'

    ALL = [NOT_CANCELLABLE, PROVIDER_UNAVAILABLE, CANCEL_REJECTED].freeze
  end

  # Language of the printable notes.
  module PromissoryNoteDocumentLocale
    TR = 'tr-TR'
    EN = 'en-GB'

    ALL = [TR, EN].freeze
  end

  # Webhook events of a note (payment.* envelope, payload promissoryNote).
  module PromissoryNoteEvents
    PAID = 'payment.promissory_note.paid'
    PROTESTED = 'payment.promissory_note.protested'
    CANCELLED = 'payment.promissory_note.cancelled'

    ALL = [PAID, PROTESTED, CANCELLED].freeze
  end

  # Plan rules of a PROMISSORY_NOTE payment checked before sending: either a schedule of
  # { amount, dueDate } rows or a noteCount, never both. That a due date lies in the future and that
  # the note count fits your provider connection is checked by the gateway.
  module PromissoryNotePlan
    DUE_DATE_PATTERN = /\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/
    NOTE_COUNT_PATTERN = /\A[1-9][0-9]?\z/
    SERIAL_NUMBER_PATTERN = /\A[A-Za-z0-9-]{4,64}\z/

    module_function

    # 1–24 rows { amount, dueDate }: positive minor-unit strings, YYYY-MM-DD calendar dates in
    # non-decreasing order. Returns string-keyed copies of the rows.
    def schedule!(rows, path = 'promissoryNote.schedule')
      raise ConfigurationError, "#{path} must be a nonempty list of { amount, dueDate } rows" unless rows.is_a?(Array) && !rows.empty?
      if rows.size > PROMISSORY_NOTE_MAX_SCHEDULE_ITEMS
        raise ConfigurationError, "#{path} can have at most #{PROMISSORY_NOTE_MAX_SCHEDULE_ITEMS} rows"
      end

      previous = nil
      rows.each_with_index.map do |row, index|
        row_path = "#{path}[#{index}]"
        raise ConfigurationError, "#{row_path} must be an object { amount, dueDate }" unless row.is_a?(Hash)

        data = row.transform_keys(&:to_s)
        raise ConfigurationError, "#{row_path} has unknown fields; a row is { amount, dueDate }" unless (data.keys - %w[amount dueDate]).empty?

        Money.minor(data['amount'])
        raise ConfigurationError, "#{row_path}.dueDate must be a calendar date in YYYY-MM-DD form" unless calendar_date?(data['dueDate'])
        raise ConfigurationError, "#{row_path}.dueDate must not be earlier than the previous row" if previous && data['dueDate'] < previous

        previous = data['dueDate']
        { 'amount' => data['amount'], 'dueDate' => data['dueDate'] }
      end
    end

    # Number of notes when no schedule is given: 1–24, sent as a string.
    def note_count!(value, path = 'promissoryNote.noteCount')
      text = value.is_a?(Integer) ? value.to_s : value
      unless text.is_a?(String) && text.match?(NOTE_COUNT_PATTERN) && text.to_i <= PROMISSORY_NOTE_MAX_SCHEDULE_ITEMS
        raise ConfigurationError, "#{path} must be a number of notes from 1 to #{PROMISSORY_NOTE_MAX_SCHEDULE_ITEMS}"
      end

      text
    end

    # The promissoryNote block of direct/payment: exactly one of schedule or noteCount; a schedule
    # must add up to amount.
    def plan!(block, amount, path = 'promissoryNote')
      raise ConfigurationError, "#{path} must be an object" unless block.is_a?(Hash)

      schedule = block['schedule']
      note_count = block['noteCount']
      raise ConfigurationError, "#{path}: send either schedule or noteCount, not both" if !schedule.nil? && !note_count.nil?
      raise ConfigurationError, "#{path} needs the plan: a schedule ([{ amount, dueDate }]) or a noteCount" if schedule.nil? && note_count.nil?
      return note_count!(note_count, "#{path}.noteCount") unless note_count.nil?

      rows = schedule!(schedule, "#{path}.schedule")
      total = rows.sum { |row| row['amount'].to_i }
      raise ConfigurationError, "#{path}.schedule must add up to amount" unless total == Money.minor(amount).to_i

      rows
    end

    # Serial numbers to cancel: 1–24 note serial numbers from payments.get_promissory_notes.
    def serial_numbers!(values)
      unless values.is_a?(Array) && !values.empty? && values.size <= PROMISSORY_NOTE_MAX_SCHEDULE_ITEMS
        raise ConfigurationError, "serial_numbers must list 1 to #{PROMISSORY_NOTE_MAX_SCHEDULE_ITEMS} serial numbers; leave it out to cancel every open note"
      end
      unless values.all? { |value| value.is_a?(String) && value.match?(SERIAL_NUMBER_PATTERN) }
        raise ConfigurationError, 'serial_numbers contains an invalid serial number (letters, digits and -, 4 to 64 characters)'
      end

      values.dup
    end

    def document_locale!(value)
      return value if PromissoryNoteDocumentLocale::ALL.include?(value)

      raise ConfigurationError, "locale must be one of #{PromissoryNoteDocumentLocale::ALL.join(', ')}"
    end

    def calendar_date?(value)
      match = value.is_a?(String) && DUE_DATE_PATTERN.match(value)
      match ? Date.valid_date?(match[1].to_i, match[2].to_i, match[3].to_i) : false
    end

    private_class_method :calendar_date?
  end
end
