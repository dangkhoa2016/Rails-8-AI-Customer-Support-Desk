# frozen_string_literal: true
require 'test_helper'
require 'json'
require 'digest'

class KnowledgeScopePreviewGateTest < ActiveSupport::TestCase
  test 'sealed 80 challenge is immutable and cannot authorize experimental preview' do
    manifest_path=Rails.root.join(KnowledgeScopePreviewGate::MANIFEST)
    report_path=Rails.root.join(KnowledgeScopePreviewGate::EVIDENCE)
    results_path=Rails.root.join(KnowledgeScopePreviewGate::RESULTS)
    report=JSON.parse(File.binread(report_path))
    manifest=JSON.parse(File.binread(manifest_path))
    assert_equal 80, manifest.fetch('cases').size
    assert_equal 'BLOCK_PREVIEW_FLAG', report.fetch('decision')
    assert_equal 3, report.fetch('combined').fetch('fp')
    assert_equal 14, report.fetch('combined').fetch('tp')
    assert_equal Digest::SHA256.file(manifest_path).hexdigest, report.fetch('sealed_manifest_sha256')
    assert_equal Digest::SHA256.file(results_path).hexdigest, report.fetch('results_sha256')
    assert_equal false, KnowledgeScopePreviewGate.eligible?
  end
end
