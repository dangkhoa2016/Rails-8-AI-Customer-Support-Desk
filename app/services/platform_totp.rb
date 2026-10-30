# frozen_string_literal: true

# Standard RFC 6238 TOTP, SHA1/6 digits/30 seconds. Secrets remain encrypted at rest.
# A separate runtime key is required; it never falls back to SECRET_KEY_BASE.
require 'openssl'
require 'securerandom'
require 'uri'

class PlatformTotp
  PERIOD = 30
  ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'

  def self.generate_secret
    SecureRandom.hex(20)
  end

  def self.base32(binary)
    bits = binary.unpack1('B*')
    bits.scan(/.{1,5}/).map { |segment| ALPHABET[segment.ljust(5, '0').to_i(2)] }.join
  end

  def self.encrypted(secret)
    raise ArgumentError, 'invalid TOTP seed' unless secret.match?(/\A[0-9a-f]{40}\z/)
    encryptor.encrypt_and_sign(secret, purpose: 'p03-platform-totp')
  end

  def self.decrypted(ciphertext)
    encryptor.decrypt_and_verify(ciphertext, purpose: 'p03-platform-totp')
  end

  def self.otp_at(secret, step)
    bytes = [secret].pack('H*')
    digest = OpenSSL::HMAC.digest('SHA1', bytes, [step].pack('Q>'))
    offset = digest.getbyte(-1) & 15
    truncated = digest.byteslice(offset, 4).unpack1('N') & 0x7fffffff
    format('%06d', truncated % 1_000_000)
  end

  def self.valid_step(secret, input, now: Time.current, last_step: nil)
    return nil unless input.to_s.match?(/\A\d{6}\z/)
    step = now.to_i / PERIOD
    (step - 1..step + 1).reverse_each do |candidate|
      next if last_step && candidate <= last_step
      return candidate if ActiveSupport::SecurityUtils.secure_compare(otp_at(secret, candidate), input)
    end
    nil
  end

  def self.enrollment_uri(email:, secret:)
    label = URI.encode_www_form_component("Rails8 Support Desk:#{email}")
    issuer = URI.encode_www_form_component('Rails8 Support Desk')
    "otpauth://totp/#{label}?secret=#{base32([secret].pack('H*'))}&issuer=#{issuer}&algorithm=SHA1&digits=6&period=30"
  end

  def self.encryptor
    hex = ENV.fetch('P03_MFA_ENCRYPTION_KEY')
    raise SecurityError, 'invalid independent MFA encryption key' unless hex.match?(/\A[0-9a-fA-F]{64}\z/)
    ActiveSupport::MessageEncryptor.new([hex].pack('H*'), cipher: 'aes-256-gcm')
  end
  private_class_method :encryptor
end
