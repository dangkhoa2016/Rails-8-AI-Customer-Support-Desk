# frozen_string_literal: true

# Exercise Rails' real CSRF validation in integration tests; do NOT disable it.
# A browser first retrieves the form/page and submits the session-bound token.
require 'nokogiri'

module CsrfRequests
  def post_with_csrf(path, params:, csrf_page: root_path)
    post path, params: params, headers: csrf_headers_from(csrf_page)
  end

  def patch_with_csrf(path, params:, csrf_page: root_path)
    patch path, params: params, headers: csrf_headers_from(csrf_page)
  end

  private

  def csrf_headers_from(page)
    get page
    assert_response :success
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]('content')
    assert token && !token.empty?, "Missing CSRF token on #{page}; do not disable forgery protection"
    { 'X-CSRF-Token' => token }
  end
end
