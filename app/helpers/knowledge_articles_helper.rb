# frozen_string_literal: true

# Presentation-only renderer for KB editorial drafts.
# Keep original body, chunk hashes, and approval state completely unchanged.
module KnowledgeArticlesHelper
  STEP_TITLES = ['Các bước xử lý', 'Handling steps'].freeze
  POLICY_TITLES = ['Chính sách có hiệu lực', 'Authoritative policy',
                   'Chính sách đã phê duyệt có liên quan', 'Relevant approved policies'].freeze
  POLICY_LINE = /\A- \*\*([A-Z][A-Z0-9-]+)\*\*\s+—\s+(.+)\z/
  STEP_SPLIT = /(?<!\S)[1-9]\d?\.\s+/
  STEP_NUMBER = /(?<!\S)([1-9]\d?)\.\s+/

  def render_editorial_kb_body(body)
    sections = body.to_s.split(/^## ([^\n]+)\r?\n/)
    title_line = sections.shift.to_s.strip
    blocks = []
    # The title is displayed separately in the editorial header.
    unless title_line.start_with?('# ')
      blocks << content_tag(:p, title_line, class: 'kb-plain') if title_line.present?
    end

    sections.each_slice(2) do |heading, text|
      next if heading.blank?
      blocks << content_tag(:h4, heading)
      copy = text.to_s.strip
      if STEP_TITLES.include?(heading.strip)
        numbered = copy.scan(STEP_NUMBER).flatten.map(&:to_i)
        split = copy.split(STEP_SPLIT)
        if split.first == '' && numbered.length >= 2 &&
            numbered == (1..numbered.length).to_a && split.length == numbered.length + 1
          blocks << content_tag(:ol, safe_join(split.drop(1).map { |item|
            content_tag(:li, item.strip)
          }), class: 'kb-step-list')
        else
          # Don't invent or discard source content if the original format differs.
          blocks << content_tag(:p, copy, class: 'kb-plain')
        end
      elsif POLICY_TITLES.include?(heading.strip)
        lines = copy.lines.map(&:strip).reject(&:empty?)
        parsed = lines.map { |line| POLICY_LINE.match(line) }
        if parsed.any? && parsed.all?
          blocks << content_tag(:ul, safe_join(parsed.map { |match|
            content_tag(:li, safe_join([content_tag(:strong, match[1]), " — #{match[2]}"]))
          }), class: 'kb-policy-list')
        else
          # Preserve all source text when it isn't the expected Markdown policy list.
          blocks << content_tag(:p, copy, class: 'kb-plain')
        end
      else
        blocks << content_tag(:p, copy, class: 'kb-plain')
      end
    end
    safe_join(blocks)
  end
end
