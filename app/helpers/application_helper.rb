module ApplicationHelper
  # Use controller identity (not path prefixes) so every nested page highlights
  # exactly one corresponding navigation item, regardless of locale/query params.
  NAV_SECTIONS = {
    'dashboard' => :overview,
    'tickets' => :tickets,
    'ticket_messages' => :tickets,
    'customers' => :customers,
    'business_records' => :customers,
    'knowledge_articles' => :knowledge,
    'knowledge_ai_search' => :ai_search
  }.freeze

  def nav_menu_link_to(label, path, section:)
    active = NAV_SECTIONS[controller_name] == section
    options = { class: active ? 'nav-menu-link is-active' : 'nav-menu-link' }
    options[:aria] = { current: 'page' } if active
    link_to(label, path, **options)
  end

  def localized_money(value, currency)
    currency == 'USD' ? format('$%.2f', value.to_i / 100.0) : "#{number_with_delimiter(value.to_i, delimiter: '.')} ₫"
  end
end
