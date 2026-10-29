# frozen_string_literal: true
require 'test_helper'
require 'json'

class KnowledgeArticlesHelperTest < ActionView::TestCase
  test 'renders Vietnamese and English handling steps as numbered lists' do
    versions = JSON.parse(File.read(Rails.root.join('review/m2_priority_editorial_proposals_20261029.json')))
    versions.fetch('revisions').each do |version|
      html = render_editorial_kb_body(version.fetch('body'))
      document = Nokogiri::HTML.fragment(html)
      lists = document.css('ol.kb-step-list')
      assert_equal 1, lists.length, "#{version.fetch('article_key')} #{version.fetch('locale')}"
      count = version.fetch('article_key') == 'NM-KB-014' ? 5 : 4
      assert_equal count, lists.first.css('li').length
      assert document.css('h4').any? { |header| ['Các bước xử lý', 'Handling steps'].include?(header.text) }
      assert_empty document.css('script')
      policy_list = document.css('ul.kb-policy-list')
      assert_equal 1, policy_list.size, "#{version.fetch('article_key')} #{version.fetch('locale')}"
      policy_ids = version.fetch('policy_refs') + version.fetch('clarification_refs')
      assert_equal policy_ids, policy_list.first.css('strong').map(&:text)
      assert_equal policy_ids.length, policy_list.first.css('li').length
      refute_includes policy_list.first.text, '**'
    end
  end

  test 'escapes source HTML instead of executing it' do
    html = render_editorial_kb_body(
      "# Draft\n\n## Handling steps\n1. <script>alert('XSS')</script> 2. Review safely\n\n## Evidence\n<img src=x onerror=alert(1)>\n"
    )
    document = Nokogiri::HTML.fragment(html)
    assert_empty document.css('script')
    assert_empty document.css('img')
    assert_equal 2, document.css('ol.kb-step-list li').size
    assert_includes html, '&lt;script&gt;'
    assert_includes html, '&lt;img'
  end

  test 'policy renderer escapes untrusted HTML in descriptions' do
    html = render_editorial_kb_body(
      "# Article\n\n## Authoritative policy\n- **TF-POL-002** — <img src=x onerror=alert(1)> must not execute\n"
    )
    doc = Nokogiri::HTML.fragment(html)
    assert_equal ['TF-POL-002'], doc.css('ul.kb-policy-list strong').map(&:text)
    assert_empty doc.css('img')
    assert_includes html, '&lt;img'
  end

  test 'falls back to plain text when step sequence is broken' do
    html = render_editorial_kb_body("# A\n\n## Handling steps\n1. First 3. Third\n")
    document = Nokogiri::HTML.fragment(html)
    assert_empty document.css('ol')
    assert_includes document.text, '1. First 3. Third'
  end
end
