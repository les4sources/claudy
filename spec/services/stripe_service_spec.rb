require "rails_helper"

# Le Singleton mono-compte était le point bloquant : tant qu'il n'y avait qu'une
# clé, il n'y avait pas de place pour le compte de Tranche de Vie.
RSpec.describe StripeService do
  it "rend un service par compte" do
    expect(described_class.for(:claudy).account_key).to eq(:claudy)
    expect(described_class.for(:tranche_de_vie).account_key).to eq(:tranche_de_vie)
  end

  # Les deux appelants existants ne doivent pas changer de comportement : cette
  # tranche ne rouvre pas des chemins de paiement en production pour une raison
  # d'architecture interne.
  it "garde `instance` compatible, pointé sur Claudy" do
    expect(described_class.instance.account_key).to eq(:claudy)
  end

  it "refuse un compte inconnu par son nom" do
    expect { described_class.for(:inexistant) }.to raise_error(described_class::UnknownAccount, /inconnu/)
  end

  # Échouer au fond de la bibliothèque Stripe sur une authentification refusée
  # ne dit rien à personne.
  it "dit quelle variable d'environnement manque" do
    expect {
      described_class.for(:tranche_de_vie).api_key
    }.to raise_error(described_class::MissingKey, /STRIPE_API_KEY_TRANCHE_DE_VIE/)
  end
end
