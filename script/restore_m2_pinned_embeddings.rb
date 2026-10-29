# frozen_string_literal: true
# Restore frozen Qwen3 embeddings from verified M2 dump, never historical row IDs.
require 'digest'
require 'json'
require 'time'
raise 'synthetic development only' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
dump = Rails.root.join('checkpoints/M2_DUAL_QWEN3_4B_REAL_EMBEDDINGS_DB_20261029.dump')
dump_sha = '9b6a218943b81d35ba61e60c92bfea6d171ca9c49517371e6ddedd18e6d0c4ae'
model = 'Qwen/Qwen3-Embedding-4B'
revision = '5cf2132abc99cad020ac570b19d031efec650f2b'
raise 'wrong pinned historical backup' unless Digest::SHA256.file(dump).hexdigest == dump_sha
raise 'M3 dataset drift' unless Digest::SHA256.file(Rails.root.join('data/m3_synthetic_tickets.json')).hexdigest ==
  '398e3de1fe231eaa6baabded10183502ed8551f33869c188d534e16bfe2c81fd'
raise 'unknown adapter' unless ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'

# Pg_restore exports COPY; all identity fields here are scalar, unescaped keys.
def copy_rows(file, table)
  rows = []
  columns = nil
  inside = false
  File.foreach(file) do |line|
    if line.start_with?("COPY public.#{table} (")
      columns = line.split('(', 2).last.split(')', 2).first.split(', ')
      inside = true
    elsif inside && line.chomp == '\\.'
      break
    elsif inside
      fields = line.chomp.split("\t", -1)
      raise "source COPY shape changed: #{table}" unless fields.length == columns.length
      rows << columns.zip(fields).to_h
    end
  end
  raise "missing source table: #{table}" unless columns
  rows
end

base = '/tmp/m2_84_restore_source'
orgs = copy_rows("#{base}/organizations.sql", 'organizations').to_h { |r| [r.fetch('id'), r] }
articles = copy_rows("#{base}/knowledge_articles.sql", 'knowledge_articles').to_h { |r| [r.fetch('id'), r] }
versions = copy_rows("#{base}/knowledge_article_versions.sql", 'knowledge_article_versions').to_h { |r| [r.fetch('id'), r] }
chunks = copy_rows("#{base}/knowledge_chunks.sql", 'knowledge_chunks').to_h { |r| [r.fetch('id'), r] }
embeddings = copy_rows('/tmp/m2-approved-84-embedding-copy.sql', 'knowledge_chunk_embeddings')
raise 'source must have exactly 84 unique vectors' unless embeddings.size == 84 &&
  embeddings.map { |e| e.fetch('knowledge_chunk_id') }.uniq.size == 84

target_orgs = Organization.where(slug: %w[teamflow-cloud novamart-store]).index_by(&:slug)
raise 'tenant count mismatch' unless target_orgs.size == 2
raise 'KB approval changed' unless KnowledgeArticleVersion.where(status: 'approved', version_number: 2).count == 12
raise 'approved chunk count changed' unless
  KnowledgeChunk.joins(:knowledge_article_version)
    .where(knowledge_article_versions: {status: 'approved', version_number: 2}).count == 84

seen = {}
links = embeddings.map do |e|
  id = e.fetch('organization_id')
  old_org = orgs.fetch(id)
  slug = old_org.fetch('slug')
  raise 'backup tenant unexpected' unless target_orgs.key?(slug) && old_org['policy_version'] == '1.0.0'
  old_chunk = chunks.fetch(e.fetch('knowledge_chunk_id'))
  old_version = versions.fetch(old_chunk.fetch('knowledge_article_version_id'))
  old_article = articles.fetch(old_version.fetch('knowledge_article_id'))
  raise 'source cross-tenant link' unless
    old_chunk.fetch('organization_id') == id &&
    old_version.fetch('organization_id') == id && old_article.fetch('organization_id') == id
  raise 'source version not approved' unless old_version.fetch('status') == 'approved' &&
    old_version.fetch('version_number') == '2'
  raise 'untrusted model' unless e.fetch('model_id') == model && e.fetch('model_revision') == revision
  raise 'source content digest mismatch' unless e.fetch('content_sha256') == old_chunk.fetch('sha256')
  org = target_orgs.fetch(slug)
  article = KnowledgeArticle.find_by!(organization_id: org.id, article_key: old_article.fetch('article_key'))
  version = KnowledgeArticleVersion.find_by!(organization_id: org.id,
    knowledge_article_id: article.id, locale: old_version.fetch('locale'), version_number: 2)
  raise 'current approved version SHA mismatch' unless
    version.status == 'approved' && version.sha256 == old_version.fetch('sha256') &&
    version.policy_version == '1.0.0' &&
    version.approved_at.present? && version.approved_by.present? &&
    version.active_on?(Date.new(2026, 10, 29)) &&
    Digest::SHA256.hexdigest(version.body) == version.sha256
  chunk = KnowledgeChunk.find_by!(organization_id: org.id,
    knowledge_article_version_id: version.id, chunk_index: Integer(old_chunk.fetch('chunk_index')))
  raise 'current chunk SHA mismatch' unless chunk.sha256 == old_chunk.fetch('sha256') &&
    Digest::SHA256.hexdigest(chunk.body) == chunk.sha256
  key = [slug, article.article_key, version.locale, chunk.chunk_index]
  raise 'duplicate natural identity' if seen[key]
  seen[key] = true
  literal = e.fetch('embedding')
  raise 'invalid vector syntax' unless literal.start_with?('[') && literal.end_with?(']')
  dimensions = literal[1...-1].split(',')
  raise 'invalid vector dimension' unless dimensions.length == 2560 &&
    dimensions.all? { |x| Float(x).finite? }
  {organization_id: org.id, knowledge_chunk_id: chunk.id,
   model_id: model, model_revision: revision, content_sha256: chunk.sha256,
   embedding: literal, generated_at: Time.parse(e.fetch('generated_at') + ' UTC')}
end
raise 'incomplete source mapping' unless links.length == 84 && seen.size == 84

before = {tickets: Ticket.count, messages: TicketMessage.count,
          approved: KnowledgeArticleVersion.where(status: 'approved').count}
if true # PRECHECK ONLY: no database writes in this stage
  puts JSON.pretty_generate(status: 'PASS_M2_RESTORE_PREFLIGHT_NO_WRITES',
    historical_dump_sha256: dump_sha, model_id: model, model_revision: revision,
    source_embeddings: links.size, dimensions: 2560,
    mapped_by: 'tenant_slug_article_key_locale_chunk_index_and_SHA256',
    target_tickets: before[:tickets], target_messages: before[:messages],
    current_embeddings: KnowledgeChunkEmbedding.count)
  exit(0)
end
# Historical M2 vectors remain NOT_RESTORED; no database writes are performed here.
