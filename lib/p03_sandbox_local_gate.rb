# frozen_string_literal: true

# Defense in depth for port 3078. Must also bind server to 127.0.0.1.
class P03SandboxLocalGate
  def initialize(app)
    @app = app
  end

  def call(env)
    host = env.fetch('HTTP_HOST', '').split(':').first
    peer = env.fetch('REMOTE_ADDR', '')
    forwarded = %w[HTTP_X_FORWARDED_HOST HTTP_FORWARDED HTTP_X_FORWARDED_FOR]
    if !%w[127.0.0.1 localhost].include?(host) ||
        !%w[127.0.0.1 ::1].include?(peer) ||
        forwarded.any? { |key| env[key].to_s != '' }
      return [403, {'content-type' => 'text/plain', 'cache-control' => 'no-store'}, ['Sandbox: loopback only']]
    end
    @app.call(env)
  end
end
