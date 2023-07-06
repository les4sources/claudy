class ProductDecorator < ApplicationDecorator
  delegate_all

  def price
    h.humanized_money_with_symbol(object.price)
  end

  def stock
    case object.stock
    when -1
      "∞"
    else
      object.stock
    end
  end
end
