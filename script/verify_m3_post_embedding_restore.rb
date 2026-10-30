# frozen_string_literal: true
# Independent read-only post-restore verification. No Modal calls or DB writes.
require 'json'
require 'digest'
require 'time'

raise 'synthetic development only' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
connection = ActiveRecord::Base.connection
raise 'unexpected database' unless connection.current_database == 'rails8_ai_support_desk_development'
expected_model = ModalEmbeddingClient::MODEL_ID
expected_revision = ModalEmbeddingClient::MODEL_REVISION
expected_dataset_sha = '398e3de1fe231eaa6baabded10183502ed8551f33869c188d534e16bfe2c81fd'
actual_dataset_sha = Digest::SHA256.file(Rails.root.join('data/m3_synthetic_tickets.json')).hexdigest
raise 'M3 dataset changed' unless expected_dataset_sha == actual_dataset_sha

counts = {
  organizations: Organization.count,
  customers: Customer.count,
  tf_invoices: TfInvoice.count,
  nm_orders: NmOrder.count,
  tickets: Ticket.count,
  messages: TicketMessage.count,
  m3_seed_audits: AuditEvent.where(action: 'synthetic.ticket_seeded').count,
  kb_articles: KnowledgeArticle.count,
  kb_versions: KnowledgeArticleVersion.count,
  approved_kb_v2: KnowledgeArticleVersion.where(version_number: 2, status: 'approved').count,
  kb_chunks: KnowledgeChunk.count,
  embeddings: KnowledgeChunkEmbedding.count
}
expected = {organizations: 2, customers: 100, tf_invoices: 80, nm_orders: 120,
  tickets: 240, messages: 440, m3_seed_audits: 240, kb_articles: 100,
  kb_versions: 212, approved_kb_v2: 12, kb_chunks: 1484, embeddings: 84}
raise "source business or KB count drift #{counts}" unless counts == expected

model_rows = connection.exec_query(
  "SELECT o.slug, COUNT(*) AS vectors, MIN(vector_dims(e.embedding)) AS min_dimension,
   MAX(vector_dims(e.embedding)) AS max_dimension, COUNT(DISTINCT e.knowledge_chunk_id) AS unique_chunks
   FROM knowledge_chunk_embeddings e
   JOIN organizations o ON o.id=e.organization_id
   JOIN knowledge_chunks c ON c.id=e.knowledge_chunk_id AND c.organization_id=e.organization_id
   JOIN knowledge_article_versions v ON v.id=c.knowledge_article_version_id
       AND v.organization_id=c.organization_id
   JOIN knowledge_articles a ON a.id=v.knowledge_article_id AND a.organization_id=e.organization_id
   WHERE v.status='approved' AND v.version_number=2 AND c.sha256=e.content_sha256
       AND e.model_id=#{connection.quote(expected_model)}
       AND e.model_revision=#{connection.quote(expected_revision)}
   GROUP BY o.slug ORDER BY o.slug"
).to_a
expected_tenants = {'novamart-store' => 56, 'teamflow-cloud' => 28}
raise 'tenant-vector mismatch' unless model_rows.to_h { |r| [r['slug'],r['vectors']] } == expected_tenants
raise 'invalid pgvector width or duplicate chunks' unless model_rows.all? { |r|
  r['min_dimension'] == 2560 && r['max_dimension'] == 2560 &&
    r['unique_chunks'] == r['vectors']
}
raise 'answerability must remain blocked' if KnowledgeScopePreviewGate.eligible?
raise 'M3 tenants drift' unless Organization.all.all? { |o| Ticket.where(organization_id: o.id).count == 120 }

puts JSON.pretty_generate(status: 'PASS_M2_VECTORS_M3_SYNTHETIC_RESTORE_READONLY',
  captured_utc: Time.now.utc.iso8601,
  source_m3_sha256: actual_dataset_sha,
  model_id: expected_model, model_revision: expected_revision,
  counts: counts, tenant_vector_checks: model_rows,
  answerability_gate: 'BLOCKED', gpu_calls: 0, database_writes: 0)
