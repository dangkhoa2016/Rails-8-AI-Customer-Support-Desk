module ApplicationHelper
  def localized_money(value, currency)
    currency == 'USD' ? format('$%.2f', value.to_i / 100.0) : "#{number_with_delimiter(value.to_i, delimiter: '.')} ₫"
  end
end
