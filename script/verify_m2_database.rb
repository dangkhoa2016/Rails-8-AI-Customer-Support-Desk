# Execute ONLY with a running Rails 8 + PostgreSQL database after M1 and M2 seeds.
require 'json'
require 'digest'

expected = {'teamflow-cloud' => 50, 'novamart-store' => 50}
result = {status: 'PASS', tenant_counts: {}, embeddings: 'NOT_RUN',
          requires_manual_article_approval: true}
expected.each do |slug, n|
  org = Organization.find_by!(slug: slug)
  arts = KnowledgeArticle.where(organization_id: org.id)
  vs = KnowledgeArticleVersion.where(organization_id: org.id)
  chunks = KnowledgeChunk.where(organization_id: org.id)
  raise "KB articles mismatch #{slug}" unless arts.count == n
  raise "KB versions mismatch #{slug}" unless vs.count == n * 2
  raise "KB chunks mismatch #{slug}" unless chunks.count == n * 2 * 7
  vs.find_each do |v|
    raise 'bad content hash' unless Digest::SHA256.hexdigest(v.body) == v.sha256
    raise 'chunk mismatch' unless v.knowledge_chunks.order(:chunk_index).pluck(:body).join == v.body
    raise 'unreviewed KB got published' if v.status == 'approved' && (v.approved_by.nil? || v.approved_at.nil?)
  end
  result[:tenant_counts][slug] = {articles: arts.count, versions: vs.count,
                                  chunks: chunks.count, approved: vs.where(status: 'approved').count}
end
puts JSON.pretty_generate(result)
