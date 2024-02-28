class PaymentDecorator < ApplicationDecorator
  delegate_all

  def amount
    h.number_to_currency(object.amount)
  end

  def payment_method
    case object.payment_method
    when "cash"
      "Liquide"
    when "bank_transfer"
      "Virement"
    when "airbnb"
      "Airbnb"
    end
  end
end
