# frozen_string_literal: true
require 'test_helper'
require Rails.root.join('lib/private_colab_preview_gate')
require 'rack/mock'

class PrivateColabPreviewGateTest < ActiveSupport::TestCase
  setup do
    fake = ->(_env) { [200, { 'x-frame-options' => 'SAMEORIGIN',
      'set-cookie' => 'demo_session=abc; path=/; HttpOnly; SameSite=Lax' }, ['SAFE_APP']] }
    @app = PrivateColabPreviewGate.new(fake, password: 'preview-private-' + 'z' * 45)
    @client = Rack::MockRequest.new(@app)
  end

  test 'unauthorized access is denied; correct form password unlocks' do
    redirect = @client.get('/demo/sign_in', 'HTTP_HOST' => '127.0.0.1')
    assert_equal 303, redirect.status
    assert_equal PrivateColabPreviewGate::LOGIN_PATH, redirect['location']
    form = @client.get(PrivateColabPreviewGate::LOGIN_PATH, 'HTTP_HOST' => '127.0.0.1')
    assert_equal 200, form.status
    nonce = form.body[/name="nonce" value="([^"]+)"/, 1]
    assert nonce.present?
    fake_cookie = @client.get('/demo/sign_in', 'HTTP_HOST' => '127.0.0.1',
      'HTTP_COOKIE' => "#{PrivateColabPreviewGate::COOKIE}=#{nonce}")
    assert_equal 303, fake_cookie.status # A CSRF token must NEVER grant a session.
    wrong = @client.post(PrivateColabPreviewGate::LOGIN_PATH, 'HTTP_HOST' => '127.0.0.1',
      params: { nonce: nonce, preview_password: 'wrong' })
    assert_equal 200, wrong.status
    assert_includes wrong.body, 'Invalid password'
    good = @client.post(PrivateColabPreviewGate::LOGIN_PATH, 'HTTP_HOST' => '127.0.0.1',
      params: { nonce: nonce, preview_password: 'preview-private-' + 'z' * 45 })
    assert_equal 303, good.status
    cookie = good['set-cookie'].split(';').first
    response = @client.get('/demo/sign_in', 'HTTP_HOST' => '127.0.0.1', 'HTTP_COOKIE' => cookie)
    assert_equal 200, response.status
    assert_equal 'SAFE_APP', response.body
    assert_nil response['x-frame-options']
    assert_match(/frame-ancestors https:\/\/colab\.research\.google\.com/, response['content-security-policy'])
  end

  test 'Colab-specific host permits partitioned cookies only on 3068' do
    host = '3068-synthetic-session.us-west4.prod.r.colab.dev'
    assert PrivateColabPreviewGate::COLAB_HOST.match?(host)
    refute PrivateColabPreviewGate::COLAB_HOST.match?('3069-synthetic-session.us-west4.prod.r.colab.dev')
    refute PrivateColabPreviewGate::COLAB_HOST.match?('3068-anything.evil.test')
    form = @client.get(PrivateColabPreviewGate::LOGIN_PATH, 'HTTP_HOST' => host)
    assert_equal 200, form.status
    nonce = form.body[/name="nonce" value="([^"]+)"/, 1]
    good = @client.post(PrivateColabPreviewGate::LOGIN_PATH, 'HTTP_HOST' => host,
      params: { nonce: nonce, preview_password: 'preview-private-' + 'z' * 45 })
    assert_equal 303, good.status
    assert_includes good['set-cookie'], 'Secure; Partitioned'
    cookie = good['set-cookie'].split(';').first
    response = @client.get('/demo/sign_in', 'HTTP_HOST' => host, 'HTTP_COOKIE' => cookie)
    assert_equal 200, response.status
    assert_includes response['set-cookie'], 'SameSite=None; Secure; Partitioned'
    refute_includes response['set-cookie'], 'SameSite=Lax'
  end

  test 'rejects unknown host' do
    response = @client.get(PrivateColabPreviewGate::LOGIN_PATH, 'HTTP_HOST' => 'other.invalid')
    assert_equal 403, response.status
  end
  test 'exact Cloudflare hostname allows password-protected read-only demo only' do
    hostname = 'brief-mango-bridge.trycloudflare.com'
    demo = ->(_env) { [200, {'content-type' => 'text/plain'}, ['SAFE_APP']] }
    gate = PrivateColabPreviewGate.new(demo, password: 'private-' + 'x' * 40,
      tunnel_host: hostname, read_only_tunnel: true)
    req = Rack::MockRequest.new(gate)
    forbidden = req.get('/__private_preview/sign_in', 'HTTP_HOST' => 'other-foo.trycloudflare.com')
    assert_equal 403, forbidden.status
    pre = req.get('/tickets', 'HTTP_HOST' => hostname)
    assert_equal 303, pre.status
    form = req.get(PrivateColabPreviewGate::LOGIN_PATH, 'HTTP_HOST' => hostname)
    assert_equal 200, form.status
    nonce = form.body[/name="nonce" value="([^"]+)"/, 1]
    login = req.post(PrivateColabPreviewGate::LOGIN_PATH, 'HTTP_HOST' => hostname,
      params: {nonce: nonce, preview_password: 'private-' + 'x' * 40})
    assert_equal 303, login.status
    assert_includes login['set-cookie'], 'SameSite=Lax; Secure'
    cookie = login['set-cookie'].split(';').first
    read = req.get('/tickets', 'HTTP_HOST' => hostname, 'HTTP_COOKIE' => cookie)
    assert_equal 200, read.status
    approval = req.post('/knowledge_articles/42/approve', 'HTTP_HOST' => hostname, 'HTTP_COOKIE' => cookie)
    assert_equal 405, approval.status
    ticket = req.post('/tickets', 'HTTP_HOST' => hostname, 'HTTP_COOKIE' => cookie)
    assert_equal 405, ticket.status
    ai = req.post('/kb/ai-search', 'HTTP_HOST' => hostname, 'HTTP_COOKIE' => cookie)
    assert_equal 200, ai.status
  end

  test 'Cloudflare preview GPU budget is global across cookie sessions' do
    host = 'brief-mango-bridge.trycloudflare.com'
    handler = ->(_env) { [200, {}, ['OK']] }
    gate = PrivateColabPreviewGate.new(handler, password: 'private-' + 'x' * 40,
      tunnel_host: host, read_only_tunnel: true)
    req = Rack::MockRequest.new(gate)
    form = req.get(PrivateColabPreviewGate::LOGIN_PATH, 'HTTP_HOST' => host)
    nonce = form.body[/name="nonce" value="([^"]+)"/, 1]
    login = req.post(PrivateColabPreviewGate::LOGIN_PATH, 'HTTP_HOST' => host,
      params: {nonce: nonce, preview_password: 'private-' + 'x' * 40})
    cookie = login['set-cookie'].split(';').first
    40.times do
      assert_equal 200, req.post('/kb/ai-search', 'HTTP_HOST' => host, 'HTTP_COOKIE' => cookie).status
    end
    assert_equal 429, req.post('/kb/ai-search', 'HTTP_HOST' => host, 'HTTP_COOKIE' => cookie).status
  end
end
