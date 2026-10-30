# frozen_string_literal: true
require 'digest'
require 'securerandom'

class AISearchRun < ApplicationRecord
  belongs_to :organization
  belongs_to :membership
  STATUSES = %w[queued running retrying succeeded failed].freeze
  TTL = 24.hours

  validates :status, inclusion: { in: STATUSES }
  validates :locale, inclusion: { in: %w[vi en] }
  validates :request_role, inclusion: { in: %w[owner admin agent] }
  validates :public_id, presence: true, uniqueness: true
  validates :query_text, length: { in: 12..300 }
  validates :query_sha256, presence: true
  validate :membership_matches_tenant
  validate :query_digest_unchanged

  before_validation :initialize_public_id, on: :create

  scope :visible_to, ->(member) {
    where(organization_id: member.organization_id, membership_id: member.id)
  }

  def expired?
    expires_at <= Time.current
  end

  def terminal?
    %w[succeeded failed].include?(status) || expired?
  end

  def safe_hits
    return [] unless status == 'succeeded' && !expired? && result_hits.is_a?(Array)
    result_hits.map { |v| KnowledgeRerankedRetrieval::Result.new(**v.symbolize_keys) }
  end

  private

  def initialize_public_id
    self.public_id ||= SecureRandom.uuid
    self.expires_at ||= TTL.from_now
  end

  def membership_matches_tenant
    errors.add(:membership, 'tenant mismatch') if membership && organization_id != membership.organization_id
  end

  def query_digest_unchanged
    return unless query_text && query_sha256
    errors.add(:query_sha256, 'mismatch') unless
      Digest::SHA256.hexdigest(query_text) == query_sha256
  end
end
