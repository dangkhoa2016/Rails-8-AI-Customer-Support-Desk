# frozen_string_literal: true
require 'test_helper'
require Rails.root.join('lib/private_colab_preview_gate')
require 'rack/mock'

class PrivateColabPreviewRoleSwitchTest < ActiveSupport::TestCase
  def test_read_only_tunnel_permits_only_rails_delete_override_for_session_logout
    host = 'private-role-switch.trycloudflare.com'
    app = ->(_env) { [200, { 'content-type' => 'text/plain' }, ['SAFE_DOWNSTREAM']] }
    gate = PrivateColabPreviewGate.new(app, password: 'demo-' + 'x' * 45,
      tunnel_host: host, read_only_tunnel: true)
    request = Rack::MockRequest.new(gate)

    password_form = request.get(PrivateColabPreviewGate::LOGIN_PATH, 'HTTP_HOST' => host)
    assert_equal 200, password_form.status
    nonce = password_form.body[/name="nonce" value="([^"]+)"/, 1]
    assert nonce.present?
    login = request.post(PrivateColabPreviewGate::LOGIN_PATH, 'HTTP_HOST' => host,
      params: {nonce: nonce, preview_password: 'demo-' + 'x' * 45})
    assert_equal 303, login.status
    cookie = login['set-cookie'].split(';').first
    headers = { 'HTTP_HOST' => host, 'HTTP_COOKIE' => cookie }

    assert_equal 200, request.post('/demo/sign_out', headers.merge(
      params: {'_method' => 'delete', 'authenticity_token' => 'synthetic-csrf-test'})).status
    assert_equal 200, request.delete('/demo/sign_out', headers).status

    assert_equal 405, request.post('/demo/sign_out', headers).status
    assert_equal 405, request.post('/demo/sign_out', headers.merge(
      params: {'_method' => 'patch'})).status
    assert_equal 405, request.post('/tickets', headers.merge(
      params: {'_method' => 'delete'})).status
    assert_equal 405, request.post('/knowledge_articles/42/approve', headers.merge(
      params: {'_method' => 'delete'})).status
    assert_equal 405, request.patch('/tickets/42/status', headers).status
    assert_equal 403, request.post('/demo/sign_out', headers.merge(
      'HTTP_HOST' => 'other-role-switch.trycloudflare.com',
      params: {'_method' => 'delete'})).status
  end
end
