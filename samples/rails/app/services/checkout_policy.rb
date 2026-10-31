# frozen_string_literal: true

# Only operator configuration can expand form navigation; payment responses cannot.
class CheckoutPolicy
  DEFAULT_GATEWAY = 'https://api-gateway.lunixi.com'
  DNS_LABEL = '[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
  ORIGIN = %r{\Ahttps://#{DNS_LABEL}(?:\.#{DNS_LABEL})*(?::[0-9]{1,5})?\z}

  def self.form_action_sources
    origins = [ENV.fetch('LUNIXI_BASE_URL', DEFAULT_GATEWAY)]
    extra = ENV.fetch('LUNIXI_FORM_ACTION_ORIGINS', '')
    origins.concat(extra.split(',', -1)) unless extra.empty?
    origins.each do |origin|
      uri = ORIGIN.match?(origin) ? URI.parse(origin) : nil
      unless uri && uri.host.length <= 253 && uri.port.between?(1, 65_535)
        raise Lunixi::ConfigurationError, 'Form actions require explicit HTTPS origins without paths'
      end
    end
    origins.uniq.join(' ')
  rescue URI::InvalidURIError
    raise Lunixi::ConfigurationError, 'Invalid form-action origin'
  end
end
