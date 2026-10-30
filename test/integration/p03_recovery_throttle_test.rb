# frozen_string_literal: true
require 'test_helper'

class P03RecoveryThrottleTest < ActiveSupport::TestCase
  PASS = 'P03-Synthetic-Protected-Password2026!'

  setup do
    @env_prior = {
      'P03_RECOVERY_TEST_MODE' => ENV['P03_RECOVERY_TEST_MODE'],
      'P03_THROTTLE_TEST_MODE' => ENV['P03_THROTTLE_TEST_MODE'],
      'P03_MFA_ENCRYPTION_KEY' => ENV['P03_MFA_ENCRYPTION_KEY'],
      'P03_THROTTLE_HMAC_KEY' => ENV['P03_THROTTLE_HMAC_KEY']
    }
    ENV['P03_RECOVERY_TEST_MODE'] = 'YES'
    ENV['P03_THROTTLE_TEST_MODE'] = 'YES'
    ENV['P03_MFA_ENCRYPTION_KEY'] = 'a' * 64
    ENV['P03_THROTTLE_HMAC_KEY'] = 'b' * 64
    @target = operator('target')
    @first = operator('first')
    @second = operator('second')
    @seeds = {}
    [@target, @first, @second].each do |admin|
      seed = PlatformTotp.generate_secret
      admin.enroll_mfa!(secret: seed)
      @seeds[admin.id] = seed
    end
  end

  teardown do
    @env_prior&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test 'two independent operators approve MFA recovery and invalidate old sessions' do
    scoped do
      before = @target.session_version
      rec = PlatformMfaRecoveryService.request!(target: @target, initiator: @first, otp: code(@first))
      assert_equal 'pending', rec.state
      assert rec.expires_at.future?
      new_seed = PlatformTotp.generate_secret
      PlatformMfaRecoveryService.approve!(recovery: rec, approver: @second,
        otp: code(@second), new_secret: new_seed)
      assert_equal 'approved', rec.reload.state
      assert_equal @second.id, rec.approver_admin_id
      assert_operator @target.reload.session_version, :>, before
      assert_equal new_seed, PlatformTotp.decrypted(@target.mfa_secret_ciphertext)
      assert @target.verify_mfa_once!(PlatformTotp.otp_at(new_seed, Time.current.to_i / 30))
      assert_equal 1, PlatformSecurityEvent.where(event_type: 'platform.mfa_recovery.requested').count
      assert_equal 1, PlatformSecurityEvent.where(event_type: 'platform.mfa_recovery.approved').count
    end
  end

  test 'requesters cannot approve their own recovery and completed approvals never repeat' do
    scoped do
      rec = PlatformMfaRecoveryService.request!(target: @target, initiator: @first, otp: code(@first))
      assert_raises(SecurityError) do
        PlatformMfaRecoveryService.approve!(recovery: rec, approver: @first,
          otp: code(@first), new_secret: PlatformTotp.generate_secret)
      end
      assert_raises(SecurityError) do
        PlatformMfaRecoveryService.approve!(recovery: rec, approver: @target,
          otp: code(@target), new_secret: PlatformTotp.generate_secret)
      end
      PlatformMfaRecoveryService.approve!(recovery: rec, approver: @second,
        otp: code(@second), new_secret: PlatformTotp.generate_secret)
      assert_raises(SecurityError) do
        PlatformMfaRecoveryService.approve!(recovery: rec, approver: @second,
          otp: code(@second), new_secret: PlatformTotp.generate_secret)
      end
    end
  end

  test 'pending recovery expires after thirty minutes' do
    scoped do
      rec = PlatformMfaRecoveryService.request!(target: @target, initiator: @first, otp: code(@first))
      travel 31.minutes do
        assert_raises(SecurityError) do
          PlatformMfaRecoveryService.approve!(recovery: rec, approver: @second,
            otp: code(@second), new_secret: PlatformTotp.generate_secret)
        end
      end
      assert_equal 'pending', rec.reload.state
    end
  end

  test 'no recovery without a third independent active operator' do
    scoped do
      @second.update!(active: false)
      assert_raises(SecurityError) do
        PlatformMfaRecoveryService.request!(target: @target, initiator: @first, otp: code(@first))
      end
      assert_equal 0, PlatformMfaRecovery.count
    end
  end

  test 'PostgreSQL throttle holds counts across requests and separates scopes and source IPs' do
    scoped do
      5.times { assert PlatformLoginThrottle.allow?(scope: 'password', address: '203.0.113.24') }
      refute PlatformLoginThrottle.allow?(scope: 'password', address: '203.0.113.24')
      assert PlatformLoginThrottle.allow?(scope: 'mfa', address: '203.0.113.24')
      assert PlatformLoginThrottle.allow?(scope: 'password', address: '203.0.113.25')
      assert_equal 6, ActiveRecord::Base.connection.select_value("SELECT MAX(attempts) FROM platform_login_throttles WHERE scope='password'").to_i
      assert_equal 0, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM platform_login_throttles WHERE identity_digest='203.0.113.24'").to_i
    end
  end

  test 'audits are immutable even through direct SQL update and delete' do
    scoped do
      event = PlatformSecurityEvent.create!(platform_admin: @target,
        event_type: 'platform.mfa_recovery.test')
      assert_raises(ActiveRecord::StatementInvalid) do
        ActiveRecord::Base.transaction(requires_new: true) do
          PlatformSecurityEvent.where(id: event.id).delete_all
        end
      end
      assert_raises(ActiveRecord::StatementInvalid) do
        ActiveRecord::Base.transaction(requires_new: true) do
          PlatformSecurityEvent.where(id: event.id).update_all(event_type: 'tampered')
        end
      end
      assert_equal 'platform.mfa_recovery.test', event.reload.event_type
    end
  end

  private

  def operator(label)
    PlatformAdmin.create!(email: "p03-#{label}-recover@example.test",
      display_name: "Synthetic #{label}", password: PASS)
  end

  def code(admin)
    PlatformTotp.otp_at(@seeds.fetch(admin.id), Time.current.to_i / 30)
  end

  def scoped
    yield
  end
end
