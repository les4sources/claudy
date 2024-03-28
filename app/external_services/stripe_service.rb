class StripeService
  def create_checkout_session(email:, success_url:, cancel_url:, item: {})
    params = {
      customer_email: email,
      line_items: [{
        name: item[:name],
        amount: item[:amount],
        quantity: 1,
      }],
      metadata: metadata,
      payment_intent_data: {
        description: "Paiement pour: #{item[:name]}",
        receipt_email: email,
        metadata: {
          "Type" => "#{item[:name]}",
          "Customer email" => email,
          "Booking ID" => "#{item[:id]}",
          "source" => "Claudy"
        }
      },
      success_url: success_url,
      cancel_url: cancel_url,
    }
    Stripe::Checkout::Session.create(params)
  end
end