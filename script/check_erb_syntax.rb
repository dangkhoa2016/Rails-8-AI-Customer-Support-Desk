# frozen_string_literal: true
# A source-only structural check with Rails block helpers normalized for plain ERB.
# Rails uses Erubi and can compile <%= form_with ... do |f| %> directly;
# the stdlib ERB compiler cannot, so this only checks Ruby syntax offline.
require 'erb'
files = Dir[File.expand_path('../app/views/**/*.erb', __dir__)]
files.each do |path|
  source = File.read(path, encoding: 'UTF-8')
  source = source.gsub(/<%=\s*(form_with[^%]+do \|f\|)\s*%>/) { "<% #{$1} %>" }
  source = source.gsub('<%= yield %>', '<%= :layout_yield_placeholder %>')
  RubyVM::InstructionSequence.compile("# encoding: UTF-8\n" + ERB.new(source).src)
  puts "PASS_SOURCE_ERB #{path.sub(File.expand_path('..', __dir__) + '/', '')}"
end
puts "PASS_SOURCE_ONLY: #{files.length} ERB view templates syntactically checked; not a Rails render test"
