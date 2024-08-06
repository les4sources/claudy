class PaymentRequestsStayItem < ApplicationRecord
  belongs_to :payment_request
  belongs_to :stay_item

  
end