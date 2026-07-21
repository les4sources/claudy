class StripeService
  include Singleton

  # Catégories de paiement visibles côté Stripe (réconciliation comptable,
  # décision Michael 2026-07-21) : chaque Checkout porte une catégorie stable
  # + des références structurées vers les objets Claudy. Ajouter ici toute
  # future famille de paiement (bar, boulangerie…) plutôt qu'un texte libre.
  CATEGORIES = %w[sejour coworking].freeze

  def create_checkout_session(client_reference_id:, success_url:, cancel_url:, item: {}, metadata: {},
                              customer_email: nil, category: nil, references: {})
    # Stripe refuse une description vide : on ne pose la clé que si fournie.
    product_data = { name: item[:name] }
    product_data[:description] = item[:description] if item[:description].present?

    # Métadonnées du PaymentIntent — ce que la compta voit dans le dashboard et
    # les exports Stripe. Structurées et stables :
    #   categorie  : famille de paiement ("sejour", "coworking", …)
    #   payment_id : id du Payment Claudy (la clé de réconciliation exacte)
    #   references : ids métier lisibles (stay_id, coworking_pack_id, …)
    # L'ancien couple ambigu « Type » (texte libre) / « Booking ID » (qui
    # contenait en réalité le payment id) est remplacé.
    intent_metadata = {
      "source"     => "Claudy",
      "categorie"  => category.presence || "sejour",
      "payment_id" => item[:id].to_s
    }.merge(references.transform_values(&:to_s)).compact

    intent_description = ["#{(category.presence || 'sejour').capitalize} Claudy", item[:name]].join(" — ")

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
        description: intent_description,
        metadata: intent_metadata
      },
      success_url: success_url,
      cancel_url: cancel_url,
    }
    params[:customer_email] = customer_email if customer_email.present?
    Stripe::Checkout::Session.create(params)
  end
end
