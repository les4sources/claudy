require "rails_helper"

# Journal des paiements (/payments) — filtre de bruit (Michael 2026-08-20).
#
# La page servait de journal d'encaissements mais listait TOUT, y compris les
# écritures provisoires des séjours encore en attente et les paiements jamais
# encaissés de séjours annulés. Deux règles, et une seule exception :
#   * séjour « en attente » → aucune de ses lignes ;
#   * séjour « annulé » → seulement ce qui a été réellement encaissé ;
#   * paiement sans séjour (coworking, canal booking historique) → jamais masqué.
RSpec.describe "Paiements — filtre du journal", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "journal@les4sources.be", password: "password123") }
  before { sign_in user }

  def customer(nom)
    Customer.create!(email: "#{nom.parameterize}@example.com", first_name: nom, last_name: "Test")
  end

  def stay_with_payment(nom:, stay_status:, payment_status:)
    stay = Stay.create!(customer: customer(nom), source: "manual", status: stay_status,
                        arrival_date: Date.today + 3, departure_date: Date.today + 5)
    Payment.create!(stay: stay, amount_cents: 4_200, status: payment_status,
                    payment_method: "bank_transfer")
    stay
  end

  it "masque toutes les lignes d'un séjour en attente, encaissées comprises" do
    stay_with_payment(nom: "Attente Encaissee", stay_status: "pending", payment_status: "paid")
    stay_with_payment(nom: "Attente Pendante", stay_status: "pending", payment_status: "pending")

    get payments_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Attente Encaissee")
    expect(response.body).not_to include("Attente Pendante")
  end

  it "masque le paiement non encaissé d'un séjour annulé" do
    stay_with_payment(nom: "Annule Sans Sous", stay_status: "canceled", payment_status: "pending")

    get payments_path

    expect(response.body).not_to include("Annule Sans Sous")
  end

  it "conserve le paiement encaissé d'un séjour annulé — c'est de l'argent reçu" do
    stay_with_payment(nom: "Annule Encaisse", stay_status: "cancelled", payment_status: "paid")

    get payments_path

    expect(response.body).to include("Annule Encaisse")
  end

  it "conserve les paiements d'un séjour confirmé, quel que soit leur statut" do
    stay_with_payment(nom: "Confirme Pendant", stay_status: "confirmed", payment_status: "pending")

    get payments_path

    expect(response.body).to include("Confirme Pendant")
  end

  it "n'écarte jamais un paiement sans séjour" do
    pack_customer = customer("Cleo Coworking")
    pack = CoworkingPack.create!(customer: pack_customer, days_total: 5, payment_method: "card")
    Payment.create!(coworking_pack: pack, amount_cents: 2_000, status: "pending",
                    payment_method: "bank_transfer")

    get payments_path

    expect(response.body).to include("Cleo Coworking")
  end
end
