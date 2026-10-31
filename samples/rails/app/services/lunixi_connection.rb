# frozen_string_literal: true

class LunixiConnection
  def self.client
    Rails.configuration.x.lunixi_client ||= Lunixi::Client.new(
      base_url: ENV.fetch('LUNIXI_BASE_URL', 'https://api-gateway.lunixi.com'),
      key_id: ENV.fetch('LUNIXI_KEY_ID'),
      private_key: File.read(ENV.fetch('LUNIXI_PRIVATE_KEY_PATH'))
    )
  end
end
