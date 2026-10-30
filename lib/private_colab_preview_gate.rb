# frozen_string_literal: true
# Password form for a PRIVATE Colab iframe (cross-origin Basic Auth prompts are blocked).
# Protects the otherwise passwordless synthetic demo. No API credentials are exposed.
require 'rack'
require 'openssl'
require 'securerandom'
require 'uri'

class PrivateColabPreviewGate
  LOGIN_PATH = '/__private_preview/sign_in'
  COOKIE = 'rails8_private_preview'
  DURATION = 3600
  COLAB_HOST = /\A3068-[a-z0-9-]+\.[a-z0-9-]+\.prod\.r\.colab\.dev\z/
  LEGACY_HOST = /\A[a-z0-9-]+-3068-colab\.googleusercontent\.com\z/
  FRAME_CSP = 'frame-ancestors https://colab.research.google.com https://*.googleusercontent.com https://*.colab.dev'

  def initialize(app, password:, tunnel_host: nil, read_only_tunnel: false)
    raise 'Weak preview password' unless password.to_s.bytesize >= 30
    @app, @password = app, password
    @tunnel_host = tunnel_host.to_s
    @read_only_tunnel = !!read_only_tunnel
    if @read_only_tunnel && !@tunnel_host.match?(/\A[a-z0-9-]+\.trycloudflare\.com\z/)
      raise 'Exact Cloudflare hostname missing for read-only tunnel'
    end
    @search_lock, @search_count = Mutex.new, 0
    @failures, @lock = {}, Mutex.new
  end

  def call(env)
    request = Rack::Request.new(env)
    return respond(403, 'Unrecognized preview host') unless allowed_host?(request.host)
    if tunnel?(request.host) && @read_only_tunnel
      # Rails button_to(method: :delete) sends a POST form with _method=delete.
      # This changes only the demo session, never tenant or business records.
      allowed_logout = request.path == '/demo/sign_out' && (
        request.delete? || (request.post? && request.POST['_method'] == 'delete')
      )
      allowed_write = (request.post? && %w[/demo/sign_in /kb/ai-search].include?(request.path)) ||
        allowed_logout
      if !%w[GET HEAD OPTIONS].include?(request.request_method) &&
          request.path != LOGIN_PATH && !allowed_write
        return respond(405, 'Public preview is read-only: changes disabled')
      end
    end

    if request.path == LOGIN_PATH
      return login_page if request.get?
      return login(request) if request.post?
      return respond(405, 'Method not allowed')
    end
    return redirect(LOGIN_PATH) unless valid_token?(request.cookies[COOKIE], purpose: 'session')

    # A small global (not per-cookie) budget for paid GPU requests through
    # this temporary public preview. Exhausting it fails closed with 429.
    if tunnel?(request.host) && request.post? && request.path == '/kb/ai-search'
      allowed = @search_lock.synchronize do
        if @search_count >= 40
          false
        else
          @search_count += 1
          true
        end
      end
      return respond(429, 'Public preview GPU budget exhausted') unless allowed
    end

    status, headers, body = @app.call(env)
    headers = headers.dup
    headers.delete('x-frame-options')
    headers.delete('X-Frame-Options')
    headers['content-security-policy'] = FRAME_CSP
    headers['cache-control'] = 'private, no-store'
    if colab?(request.host) && headers['set-cookie']
      cookie = headers['set-cookie']
      headers['set-cookie'] = cookie.is_a?(Array) ? cookie.map { |c| partition(c) } : partition(cookie)
    end
    [status, headers, body]
  end

  private

  def colab?(host)
    COLAB_HOST.match?(host.to_s) || LEGACY_HOST.match?(host.to_s)
  end

  def tunnel?(host)
    @read_only_tunnel && host.to_s == @tunnel_host
  end

  def allowed_host?(host)
    %w[127.0.0.1 localhost].include?(host) || colab?(host) || tunnel?(host)
  end

  def partition(raw)
    raw.to_s.gsub(/;\s*SameSite=(Lax|Strict)/i, '').gsub(/;\s*Partitioned/i, '') +
      '; SameSite=None; Secure; Partitioned'
  end

  def compare(left, right)
    left.bytesize == right.bytesize && Rack::Utils.secure_compare(left, right)
  end

  def sign(payload)
    OpenSSL::HMAC.hexdigest('SHA256', @password, payload)
  end

  def token(seconds, purpose:)
    payload = "#{purpose}:#{Time.now.to_i + seconds}:#{SecureRandom.hex(20)}"
    "#{payload}:#{sign(payload)}"
  end

  def valid_token?(value, purpose:)
    token_purpose, exp, nonce, signature = value.to_s.split(':')
    return false unless token_purpose == purpose
    return false unless exp.to_s.match?(/\A\d{10,12}\z/) &&
      nonce.to_s.match?(/\A[0-9a-f]{40}\z/) &&
      signature.to_s.match?(/\A[0-9a-f]{64}\z/)
    expires = exp.to_i
    return false unless expires.between?(Time.now.to_i, Time.now.to_i + DURATION + 60)
    compare(signature, sign("#{purpose}:#{exp}:#{nonce}"))
  end

  def login_page(error: false)
    signed_nonce = token(900, purpose: 'csrf')
    warning = error ? '<p role="alert" style="color:#ffbaba">Invalid password or expired request.</p>' : ''
    html = <<~HTML
      <!doctype html><html lang="en"><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Private AI Support Desk preview</title>
      <style>
      :root{color-scheme:dark}body{background:#0b1729;color:#e5efff;font:16px system-ui,sans-serif;padding:45px 16px}
      main{max-width:510px;margin:0 auto;background:#15243c;border:1px solid #334a68;border-radius:16px;padding:28px}
      label{display:block;margin:20px 0 8px}input{box-sizing:border-box;width:100%;padding:14px;font-size:17px;border-radius:8px;background:#0e1a2e;color:white;border:1px solid #637c9f}
      button{margin-top:22px;width:100%;padding:14px;border:0;border-radius:8px;background:#8ebaff;color:#0b1930;font-weight:700;cursor:pointer}
      p{line-height:1.6}small{color:#aebfd6}
      </style></head><body><main>
      <p>Rails 8 AI Customer Support Desk</p><h1>Private Colab preview</h1>
      <p>Enter the preview password stored privately on the Colab runtime.</p>
      #{warning}
      <form method="POST" action="#{LOGIN_PATH}" autocomplete="off">
      <input type="hidden" name="nonce" value="#{signed_nonce}">
      <label for="preview_password">Preview password</label>
      <input type="password" id="preview_password" name="preview_password" autocomplete="off" required autofocus>
      <button type="submit">Unlock preview</button>
      </form><p><small>Synthetic data only. Do not share this preview URL.</small></p>
      </main></body></html>
    HTML
    respond(200, html, type: 'text/html; charset=utf-8')
  end

  def login(request)
    origin = request.get_header('HTTP_ORIGIN').to_s
    unless origin.empty?
      begin
        return respond(403, 'Origin not allowed') unless URI.parse(origin).host == request.host
      rescue URI::InvalidURIError
        return respond(403, 'Origin not allowed')
      end
    end
    ip, now = request.ip, Time.now.to_i
    blocked = @lock.synchronize do
      failures = (@failures[ip] ||= [])
      failures.reject! { |x| x < now - 600 }
      failures.size >= 10
    end
    return respond(429, 'Preview login rate limited') if blocked

    fields = request.POST
    if valid_token?(fields['nonce'], purpose: 'csrf') && compare(fields['preview_password'].to_s, @password)
      @lock.synchronize { @failures.delete(ip) }
      secure = colab?(request.host) || tunnel?(request.host) || request.ssl?
      flags = if tunnel?(request.host)
        'SameSite=Lax; Secure'
      elsif secure
        'SameSite=None; Secure; Partitioned'
      else
        'SameSite=Lax'
      end
      cookie = "#{COOKIE}=#{token(DURATION, purpose: 'session')}; Path=/; HttpOnly; Max-Age=#{DURATION}; #{flags}"
      return [303, {'location' => '/demo/sign_in', 'set-cookie' => cookie,
                    'cache-control' => 'no-store', 'content-security-policy' => FRAME_CSP}, []]
    end

    @lock.synchronize { (@failures[ip] ||= []) << now }
    login_page(error: true)
  end

  def redirect(path)
    [303, {'location' => path, 'cache-control' => 'no-store'}, []]
  end

  def respond(status, message, type: 'text/plain; charset=utf-8')
    [status, {'content-type' => type, 'cache-control' => 'no-store',
              'x-content-type-options' => 'nosniff',
              'content-security-policy' => FRAME_CSP}, [message]]
  end
end
