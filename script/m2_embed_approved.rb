# frozen_string_literal: true
# Usage (after actual Modal deployment + editorial approval):
#   KB_ORGANIZATION_SLUG=teamflow-cloud bin/rails runner script/m2_embed_approved.rb
# Dry-run by default; write requires M2_EMBED_INGEST=YES and Modal credentials.
require 'json'
slug = ENV.fetch('KB_ORGANIZATION_SLUG')
raise 'unknown demo tenant' unless %w[teamflow-cloud novamart-store].include?(slug)
raise 'only synthetic development DB' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
organization = Organization.find_by!(slug: slug)
eligible = KnowledgeEmbeddingIngestion.eligible_chunks(organization: organization)
puts JSON.generate({ organization: slug, approved_active_chunks: eligible.count,
  mode: ENV['M2_EMBED_INGEST'] == 'YES' ? 'INGEST' : 'DRY_RUN' })
unless ENV['M2_EMBED_INGEST'] == 'YES'
  puts 'DRY_RUN: no external requests or database writes'
  exit(0)
end
client = ModalEmbeddingClient.new
result = KnowledgeEmbeddingIngestion.ingest!(organization: organization,
  client: client, max_chunks: Integer(ENV.fetch('M2_INGEST_BATCH', '8')))
puts JSON.generate(result.merge(organization: slug, model_id: client.model_id,
  model_revision: client.model_revision))
