# Passerelle Stripe — MULTI-COMPTES depuis l'issue #187.
#
# Le Singleton d'origine ne lisait qu'une clé. Tranche de Vie a son propre
# compte Stripe et ses flux doivent pouvoir entrer ici : tant que le service
# était un Singleton, il n'y avait littéralement pas de place pour un second
# compte. `StripeService.for(:claudy)` et `.for(:tranche_de_vie)` remplacent
# l'instance unique.
#
# `instance` reste disponible et pointe sur `:claudy` : les appelants existants
# — le paiement d'un séjour et l'achat d'un pack coworking — ne changent pas de
# comportement, et cette tranche ne rouvre pas des chemins de paiement en
# production pour une raison d'architecture interne.
class StripeService
  ACCOUNTS = {
    claudy: { env_key: "STRIPE_API_KEY", label: "Claudy" },
    tranche_de_vie: { env_key: "STRIPE_API_KEY_TRANCHE_DE_VIE", label: "Tranche de Vie" }
  }.freeze

  class UnknownAccount < StandardError; end
  class MissingKey < StandardError; end

  attr_reader :account_key

  def self.for(account_key)
    key = account_key.to_sym
    raise UnknownAccount, "Compte Stripe inconnu : #{account_key}." unless ACCOUNTS.key?(key)

    (@instances ||= {})[key] ||= new(key)
  end

  def self.instance = self.for(:claudy)

  def self.label_for(account_key) = ACCOUNTS.dig(account_key.to_sym, :label) || account_key.to_s

  def initialize(account_key = :claudy)
    @account_key = account_key.to_sym
  end

  # La clé est lue à l'usage et pas au démarrage : un compte non configuré ne
  # doit pas empêcher l'application de booter, il doit le dire quand on s'en
  # sert. Et le dire clairement, plutôt que d'échouer au fond de la
  # bibliothèque Stripe sur une authentification refusée.
  def api_key
    valeur = ENV[ACCOUNTS.fetch(@account_key)[:env_key]].presence
    return valeur if valeur

    raise MissingKey,
          "La clé Stripe du compte « #{self.class.label_for(@account_key)} » n'est pas configurée " \
          "(#{ACCOUNTS.fetch(@account_key)[:env_key]})."
  end

  def request_options = { api_key: api_key }

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
