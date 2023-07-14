class ExperienceDecorator < ApplicationDecorator
  delegate_all

  def price
    h.humanized_money_with_symbol(object.price)
  end
end
