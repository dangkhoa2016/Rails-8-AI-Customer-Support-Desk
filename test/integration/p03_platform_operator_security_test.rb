# frozen_string_literal: true
require 'test_helper'
require Rails.root.join('lib/p03_sandbox_local_gate')
require_relative '../support/csrf_requests'

class P03PlatformOperatorSecurityTest < ActionDispatch::IntegrationTest
  include CsrfRequests
  PASSWORD = 'Extremely-Strong-Sandbox-Operator-Pass2026!'

  setup do
    @admin = PlatformAdmin.create!(
      email: 'p03-operator@example.test', display_name: 'Synthetic Platform Operator',
      password: PASSWORD
    )
    @tenant = Organization.create!(slug: 'p03-synthetic-tenant',
      name: 'P03 Isolated Test Tenant', vertical: 'b2b_saas', currency: 'USD')
    @seed = PlatformTotp.generate_secret
  end

  test 'TOTP secret encrypted, RFC test determinism, and replay rejected' do
    with_mfa_env do
      @admin.enroll_mfa!(secret: @seed)
      refute_includes @admin.reload.mfa_secret_ciphertext, @seed
      assert_equal @seed, PlatformTotp.decrypted(@admin.mfa_secret_ciphertext)
      step = Time.current.to_i / 30
      code = PlatformTotp.otp_at(@seed, step)
      assert @admin.verify_mfa_once!(code)
      refute @admin.verify_mfa_once!(code)
      assert_equal step, @admin.reload.mfa_last_used_step
      assert_match(/\Aotpauth:\/\/totp\//, PlatformTotp.enrollment_uri(email: @admin.email, secret: @seed))
    end
  end

  test 'password-only session cannot enter platform; MFA grants only platform scope' do
    with_mfa_env do
      @admin.enroll_mfa!(secret: @seed)
      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @admin.email, password: PASSWORD}
      assert_redirected_to platform_mfa_path
      get platform_dashboard_path
      assert_redirected_to platform_sign_in_path

      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @admin.email, password: PASSWORD}
      code = PlatformTotp.otp_at(@seed, Time.current.to_i / 30)
      post_with_csrf platform_mfa_path, csrf_page: platform_mfa_path, params: {code: code}
      assert_redirected_to platform_dashboard_path
      get platform_dashboard_path
      assert_response :success
      get tickets_path
      assert_redirected_to demo_sign_in_path
      assert_equal 1, PlatformSecurityEvent.where(event_type: 'platform.login.completed').count
    end
  end

  test 'MFA rejects invalid and reused OTP, records safe audit events' do
    with_mfa_env do
      @admin.enroll_mfa!(secret: @seed)
      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @admin.email, password: PASSWORD}
      assert_redirected_to platform_mfa_path
      post_with_csrf platform_mfa_path, csrf_page: platform_mfa_path, params: {code: '000000'}
      assert_response :unauthorized
      code = PlatformTotp.otp_at(@seed, Time.current.to_i / 30)
      post_with_csrf platform_mfa_path, csrf_page: platform_mfa_path, params: {code: code}
      assert_redirected_to platform_dashboard_path
      delete platform_sign_out_path, headers: csrf_headers_from(platform_dashboard_path)
      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @admin.email, password: PASSWORD}
      assert_redirected_to platform_mfa_path
      post_with_csrf platform_mfa_path, csrf_page: platform_mfa_path, params: {code: code}
      assert_response :unauthorized
      assert_operator PlatformSecurityEvent.where(event_type: 'platform.login.mfa_rejected').count, :>=, 2
    end
  end

  test 'revoked operator cannot finish a previously issued password MFA challenge' do
    with_mfa_env do
      @admin.enroll_mfa!(secret: @seed)
      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @admin.email, password: PASSWORD}
      assert_redirected_to platform_mfa_path
      old_code = PlatformTotp.otp_at(@seed, Time.current.to_i / 30)
      headers = csrf_headers_from(platform_mfa_path)
      @admin.revoke_sessions!
      post platform_mfa_path, headers: headers, params: {code: old_code}
      assert_response :unauthorized
      get platform_dashboard_path
      assert_redirected_to platform_sign_in_path
      assert_equal 0, PlatformSecurityEvent.where(event_type: 'platform.login.completed').count
    end
  end

  test 'revoked operator sessions and lockout fail closed' do
    with_mfa_env do
      @admin.enroll_mfa!(secret: @seed)
      5.times do
        post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
          params: {email: @admin.email, password: 'wrong-attempt'}
        assert_response :unauthorized
      end
      assert @admin.reload.locked_until.future?
      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @admin.email, password: PASSWORD}
      assert_response :unauthorized

      @admin.update!(failed_sign_in_count: 0, locked_until: nil)
      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @admin.email, password: PASSWORD}
      code = PlatformTotp.otp_at(@seed, Time.current.to_i / 30)
      post_with_csrf platform_mfa_path, csrf_page: platform_mfa_path, params: {code: code}
      assert_redirected_to platform_dashboard_path
      @admin.revoke_sessions!
      get platform_dashboard_path
      assert_redirected_to platform_sign_in_path
    end
  end

  test 'idle session expiry and pending MFA challenge timeout fail closed' do
    with_mfa_env do
      @admin.enroll_mfa!(secret: @seed)
      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @admin.email, password: PASSWORD}
      assert_redirected_to platform_mfa_path
      travel 6.minutes do
        get platform_mfa_path
        assert_redirected_to platform_sign_in_path
      end
      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @admin.email, password: PASSWORD}
      code = PlatformTotp.otp_at(@seed, Time.current.to_i / 30)
      post_with_csrf platform_mfa_path, csrf_page: platform_mfa_path, params: {code: code}
      assert_redirected_to platform_dashboard_path
      travel 16.minutes do
        get platform_dashboard_path
        assert_redirected_to platform_sign_in_path
      end
    end
  end

  test 'unenrolled operator cannot obtain a sandbox session with password alone' do
    with_mfa_env do
      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @admin.email, password: PASSWORD}
      assert_response :unauthorized
      get platform_dashboard_path
      assert_redirected_to platform_sign_in_path
    end
  end

  test 'legacy production platform opt-in cannot bypass MFA or enable operator console' do
    previous = ENV['P0_PLATFORM_AUTH_ENABLE']
    ENV['P0_PLATFORM_AUTH_ENABLE'] = 'YES'
    original_env_method = Rails.method(:env)
    Rails.define_singleton_method(:env) { ActiveSupport::StringInquirer.new('production') }
    refute ApplicationController.new.send(:platform_auth_mode?)
  ensure
    Rails.define_singleton_method(:env, original_env_method) if original_env_method
    previous ? ENV['P0_PLATFORM_AUTH_ENABLE'] = previous : ENV.delete('P0_PLATFORM_AUTH_ENABLE')
  end

  test 'password rotation and active toggle invalidate a previously authenticated session' do
    with_mfa_env do
      @admin.enroll_mfa!(secret: @seed)
      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @admin.email, password: PASSWORD}
      assert_redirected_to platform_mfa_path
      post_with_csrf platform_mfa_path, csrf_page: platform_mfa_path,
        params: {code: PlatformTotp.otp_at(@seed, Time.current.to_i / 30)}
      assert_redirected_to platform_dashboard_path
      version = @admin.reload.session_version
      @admin.update!(password: 'P03-Changed-Synthetic-Password-2026!')
      assert_operator @admin.reload.session_version, :>, version
      get platform_dashboard_path
      assert_redirected_to platform_sign_in_path

      previous = @admin.session_version
      @admin.update!(active: false)
      @admin.update!(active: true)
      assert_operator @admin.reload.session_version, :>, previous
    end
  end

  test 'sandbox local gate refuses public hosts and forwarded headers' do
    gate = P03SandboxLocalGate.new(lambda { |_env| [200, {}, ['ok']] })
    valid = {'HTTP_HOST' => '127.0.0.1:3078', 'REMOTE_ADDR' => '127.0.0.1'}
    assert_equal 200, gate.call(valid)[0]
    assert_equal 403, gate.call(valid.merge('HTTP_HOST' => 'attacker.trycloudflare.com'))[0]
    assert_equal 403, gate.call(valid.merge('REMOTE_ADDR' => '192.0.2.8'))[0]
    assert_equal 403, gate.call(valid.merge('HTTP_X_FORWARDED_HOST' => 'evil.example'))[0]
  end

  private

  def with_mfa_env
    prior_auth = ENV['P0_PLATFORM_AUTH_TEST_MODE']
    prior_mfa = ENV['P03_MFA_TEST_MODE']
    prior_key = ENV['P03_MFA_ENCRYPTION_KEY']
    ENV['P0_PLATFORM_AUTH_TEST_MODE'] = 'YES'
    ENV['P03_MFA_TEST_MODE'] = 'YES'
    ENV['P03_MFA_ENCRYPTION_KEY'] = 'a' * 64
    yield
  ensure
    prior_auth ? ENV['P0_PLATFORM_AUTH_TEST_MODE'] = prior_auth : ENV.delete('P0_PLATFORM_AUTH_TEST_MODE')
    prior_mfa ? ENV['P03_MFA_TEST_MODE'] = prior_mfa : ENV.delete('P03_MFA_TEST_MODE')
    prior_key ? ENV['P03_MFA_ENCRYPTION_KEY'] = prior_key : ENV.delete('P03_MFA_ENCRYPTION_KEY')
  end
end
