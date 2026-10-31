# frozen_string_literal: true

# The gateway's informational POST must not require a cross-site session or
# browser CSRF token. It only redirects to the existing authenticated GET.
class LunixiReturnAdapter
  MAX_BYTES = 1_048_576
  PATH = %r{\A/orders/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/return\z}i

  def initialize(app)
    @app = app
  end

  def call(env)
    match = PATH.match(env.fetch('PATH_INFO', ''))
    return @app.call(env) unless env['REQUEST_METHOD'] == 'POST' && match

    headers = { 'content-type' => 'text/plain', 'content-length' => '0', 'cache-control' => 'no-store',
                'referrer-policy' => 'no-referrer', 'x-content-type-options' => 'nosniff' }
    return [413, headers, []] if env.fetch('CONTENT_LENGTH', '0').to_i > MAX_BYTES

    body = env.fetch('rack.input').read(MAX_BYTES + 1)
    return [413, headers, []] if body && body.bytesize > MAX_BYTES

    # No parameter parsing, order lookup, session access or gateway request.
    [303, headers.merge('location' => "/orders/#{match[1]}/return"), []]
  end
end
