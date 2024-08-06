class PaymentRequest < ApplicationRecord
  
  belongs_to :stay
  has_many :payment_requests_stay_items
  has_many :stay_items, through: :payment_requests_stay_items
  has_many :payments

  PAYMENT_PAID = 'paid'
  PAYMENT_PARTIALLY_PAID = 'partially_paid'
  PAYMENT_PENDING = 'pending'
  INVOICE_NOT_REQUIRED = 'not_required'
  INVOICE_TO_PROVIDE = 'to_provide'
  INVOICE_SENT = 'sent'

  def total_paid
    payments.sum(:amount_cents)
  end


  def paid?
    total_paid >= amount_cents
  end

  def partially_paid?
    total_paid > 0 && total_paid < amount_cents
  end

  def update_payment_status
    if paid?
      update(payment_status: PAYMENT_PAID)
    elsif partially_paid?
      update(payment_status: PAYMENT_PARTIALLY_PAID)
    else
      update(payment_status: PAYMENT_PENDING)
    end
  end


  def remaining_amount
    amount_cents - payments.sum(:amount_cents)
  end


end