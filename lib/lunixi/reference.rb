# frozen_string_literal: true

module Lunixi
  # Lunixi address dictionary for Türkiye (province -> district -> neighborhood). The codes fill an
  # ADDRESS input field, e.g. { provinceCode:, districtCode:, neighborhoodCode:, line: }. The answer is
  # the gateway envelope with data.items [{ code, name }]; an empty list means the data for that level
  # is not published yet.
  class Reference
    BASE = '/api/v1/reference/tr-address'
    PROVINCE_CODE_PATTERN = /\A(0[1-9]|[1-7][0-9]|8[01])\z/
    DISTRICT_CODE_PATTERN = /\A[0-9]{1,12}\z/
    attr_reader :client

    def initialize(client)
      @client = client
    end

    # Provinces with their Lunixi code (01–81).
    def list_provinces
      client.request('GET', "#{BASE}/provinces", signed: false)
    end

    # Districts of a province (province_code 01–81).
    def list_districts(province_code)
      unless province_code.is_a?(String) && province_code.match?(PROVINCE_CODE_PATTERN)
        raise ConfigurationError, 'province_code must be a two-digit province code from 01 to 81'
      end

      client.request('GET', "#{BASE}/districts", query: { provinceCode: province_code }, signed: false)
    end

    # Neighborhoods of a district (district_code from list_districts).
    def list_neighborhoods(district_code)
      unless district_code.is_a?(String) && district_code.match?(DISTRICT_CODE_PATTERN)
        raise ConfigurationError, 'district_code must be a district code (digits) from list_districts'
      end

      client.request('GET', "#{BASE}/neighborhoods", query: { districtCode: district_code }, signed: false)
    end
  end
end
