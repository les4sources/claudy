class StripeService
  include Singleton

  def create_checkout_session(client_reference_id:, success_url:, cancel_url:, item: {}, metadata: {}, customer_email: nil)
    # Stripe refuse une description vide : on ne pose la clé que si fournie.
    product_data = { name: item[:name] }
    product_data[:description] = item[:description] if item[:description].present?

    params = {
      mode: "payment",
      client_reference_id: client_reference_id,
      line_items: [{
        price_data: {
          currency: "eur",
          unit_amount: item[:amount],
          product_data: product_data
        },
        quantity: 1,
      }],
      metadata: metadata,
      payment_intent_data: {
        description: "Paiement pour: #{item[:name]}",
        metadata: {
          "Type" => "#{item[:name]}",
          "Booking ID" => "#{item[:id]}",
          "source" => "Claudy"
        }
      },
      success_url: success_url,
      cancel_url: cancel_url,
    }
    params[:customer_email] = customer_email if customer_email.present?
    Stripe::Checkout::Session.create(params)
  end
end