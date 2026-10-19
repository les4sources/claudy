require "rails_helper"

# Issue #339 — le parcours de la fiche séjour : rattacher, détacher, actualiser.
RSpec.describe "Fiche séjour — Pizza Party de Tranches de Vie", type: :request do
  include Devise::Test::IntegrationHelpers

  around do |example|
    url, key = ENV["TRANCHESDEVIE_API_URL"], ENV["TRANCHESDEVIE_API_KEY"]
    tdv_env!
    example.run
    ENV["TRANCHESDEVIE_API_URL"] = url
    ENV["TRANCHESDEVIE_API_KEY"] = key
  end

  let(:user) { User.create!(email: "agent-party@les4sources.be", password: "password123") }
  let(:customer) do
    Customer.create!(email: "alix@example.com", customer_type: "organization", organization_name: "Scouts de Namur")
  end
  let(:stay) do
    Stay.create!(customer: customer, status: "confirmed",
                 arrival_date: Date.new(2026, 10, 8), departure_date: Date.new(2026, 10, 11))
  end

  before do
    sign_in user
    LinenOrder.create!(stay: stay, kind: "double_bed", quantity: 1, price_cents: 50_000)
    stay.recompute_aggregates!
  end

  describe "la liste des candidates" do
    it "interroge Tranches de Vie sur la fenêtre des dates du séjour" do
      stub_tdv_index([tdv_order])
      get stay_party_reservations_path(stay)

      expect(response).to have_http_status(:ok)
      expect(
        a_request(:get, "#{TranchesDeVieHelpers::BASE_URL}/api/v1/orders")
          .with(query: hash_including({ "held_on_from" => "2026-10-07", "held_on_to" => "2026-10-12" }))
      ).to have_been_made
      expect(response.body).to include("Scouts de Namur")
      expect(response.body).to include("Rattacher")
    end

    it "propose aussi une party pas encore payée (réglée sur place), et la signale" do
      stub_tdv_index([tdv_unpaid_order(id: 77)])
      get stay_party_reservations_path(stay)

      expect(
        a_request(:get, "#{TranchesDeVieHelpers::BASE_URL}/api/v1/orders")
          .with(query: hash_excluding("paid"))
      ).to have_been_made
      expect(response.body).to include("Scouts de Namur")
      expect(response.body).to include("Pas encore payée")
      expect(response.body).to include("Rattacher")
    end

    it "écarte les parties annulées ou remboursées" do
      stub_tdv_index([tdv_order(id: 1, cancelled: true, party: tdv_order["party"].merge("group_name" => "Groupe annulé")),
                      tdv_order(id: 2, refunded: true, party: tdv_order["party"].merge("group_name" => "Groupe remboursé"))])
      get stay_party_reservations_path(stay)

      expect(response.body).not_to include("Groupe annulé")
      expect(response.body).not_to include("Groupe remboursé")
      expect(response.body).to include("Aucune Pizza Party sur cette période.")
    end

    it "remonte les parties du MÊME client en tête" do
      autre = tdv_order(id: 1, customer: { "id" => 9, "full_name" => "Autre", "email" => "autre@example.com", "phone_e164" => "+32499000000" })
      stub_tdv_index([autre, tdv_order(id: 2)])

      get stay_party_reservations_path(stay)
      expect(response.body.index("alix@example.com")).to be < response.body.index("autre@example.com")
    end

    it "signale une party déjà rattachée et n'offre pas de la rattacher deux fois" do
      stub_tdv_order(tdv_order(id: 1234))
      TranchesDeVie::AttachPartyReservation.new(stay: stay).run(1234)

      stub_tdv_index([tdv_order(id: 1234)])
      get stay_party_reservations_path(stay)
      expect(response.body).to include("Déjà rattachée à ce séjour")
    end

    it "affiche une erreur lisible quand Tranches de Vie ne répond pas" do
      stub_request(:get, %r{#{TranchesDeVieHelpers::BASE_URL}/api/v1/orders}).to_timeout

      get stay_party_reservations_path(stay)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("n&#39;a pas répondu à temps")
    end

    it "sans clé d'API : aucun appel sortant et l'explication à l'écran" do
      tdv_env_off!
      get stay_party_reservations_path(stay)

      expect(response.body).to include("Connexion à Tranches de Vie non configurée")
      expect(a_request(:any, //)).not_to have_been_made
    end
  end

  describe "le rattachement" do
    it "fait bouger Total séjour et Encaissé du montant de la party" do
      stub_tdv_order(tdv_order(id: 1234))

      expect { post stay_party_reservations_path(stay), params: { external_id: 1234 } }
        .to change { stay.reload.total_amount_cents }.from(50_000).to(77_000)

      expect(response).to redirect_to(stay_path(stay))
      expect(stay.amount_paid_cents).to eq(27_000)

      get stay_path(stay)
      expect(response.body).to include("Pizza Party")
      expect(response.body).to include("Scouts de Namur")
      expect(response.body).to include(ApplicationController.helpers.humanized_money_with_symbol(Money.new(77_000)))
    end

    it "refuse en clair une party déjà rattachée" do
      stub_tdv_order(tdv_order(id: 1234))
      post stay_party_reservations_path(stay), params: { external_id: 1234 }
      post stay_party_reservations_path(stay), params: { external_id: 1234 }

      follow_redirect!
      expect(response.body).to include("déjà rattachée")
    end

    # Le bloc Pizza Party est à droite, les montants à gauche (Michael,
    # 2026-10-13) : depuis la modale, la réponse remplace les deux frames.
    it "rafraîchit en Turbo Stream le bloc de droite ET les paiements" do
      stub_tdv_order(tdv_order(id: 1234))

      post stay_party_reservations_path(stay), params: { external_id: 1234 }, as: :turbo_stream

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(target="stay_#{stay.id}_extras"), %(target="stay_#{stay.id}_payments"))
      expect(response.body).to include("Pizza Party rattachée au séjour.")
      expect(response.body).to include(ApplicationController.helpers.humanized_money_with_symbol(Money.new(77_000)))
    end
  end

  describe "réglée avec le séjour" do
    it "se coche au rattachement : le total bouge, pas l'encaissé" do
      stub_tdv_order(tdv_order(id: 1234))

      post stay_party_reservations_path(stay), params: { external_id: 1234, paid_with_stay: "1" }

      expect(stay.reload.total_amount_cents).to eq(77_000)
      expect(stay.amount_paid_cents).to eq(0)
      expect(stay.party_reservations.first.paid_with_stay).to be(true)

      get stay_path(stay)
      expect(response.body).to include("Réglée avec le séjour")
      expect(response.body).not_to include("Pizza Party · Tranches de Vie")
    end

    it "se règle après coup : le paiement Tranches de Vie sort de l'encaissé, puis revient" do
      stub_tdv_order(tdv_order(id: 1234))
      TranchesDeVie::AttachPartyReservation.new(stay: stay).run(1234)
      reservation = stay.reload.party_reservations.first
      expect(stay.amount_paid_cents).to eq(27_000)

      patch stay_party_reservation_path(stay, reservation), params: { paid_with_stay: "1" }

      expect(reservation.reload.paid_with_stay).to be(true)
      expect(reservation.payment).to be_nil
      expect(stay.reload.total_amount_cents).to eq(77_000)
      expect(stay.amount_paid_cents).to eq(0)
      follow_redirect!
      expect(response.body).to include("réglée avec le séjour")

      patch stay_party_reservation_path(stay, reservation), params: { paid_with_stay: "0" }

      expect(reservation.reload.paid_with_stay).to be(false)
      expect(reservation.payment.amount_cents).to eq(27_000)
      expect(stay.reload.amount_paid_cents).to eq(27_000)
      expect(Payment.where(payment_method: Payment::TRANCHESDEVIE_METHOD).count).to eq(1)
    end

    it "se propose sur chaque candidate" do
      stub_tdv_index([tdv_order])
      get stay_party_reservations_path(stay)

      expect(response.body).to include("Réglée avec le séjour (déjà dans un paiement)")
    end
  end

  describe "le détachement" do
    it "ramène le total et l'encaissé à leur valeur d'avant" do
      stub_tdv_order(tdv_order(id: 1234))
      TranchesDeVie::AttachPartyReservation.new(stay: stay).run(1234)
      reservation = stay.reload.party_reservations.first

      expect { delete stay_party_reservation_path(stay, reservation) }
        .to change { stay.reload.total_amount_cents }.from(77_000).to(50_000)

      expect(stay.amount_paid_cents).to eq(0)
    end
  end

  describe "l'actualisation à la demande" do
    it "répercute un remboursement décidé sur Tranches de Vie" do
      stub_tdv_order(tdv_order(id: 1234))
      TranchesDeVie::AttachPartyReservation.new(stay: stay).run(1234)

      stub_tdv_order(tdv_order(id: 1234, refunded: true, refunded_at: "2026-09-25T09:00:00Z"))
      post sync_stay_party_reservations_path(stay)

      reservation = stay.reload.party_reservations.first
      expect(reservation.status).to eq("refunded")
      expect(stay.total_amount_cents).to eq(50_000)

      get stay_path(stay)
      expect(response.body).to include("Remboursée le")
    end
  end

  describe "la ligne de paiement" do
    it "porte le badge Pizza Party et n'offre ni édition ni suppression" do
      stub_tdv_order(tdv_order(id: 1234))
      TranchesDeVie::AttachPartyReservation.new(stay: stay).run(1234)

      get stay_path(stay)
      expect(response.body).to include("Pizza Party · Tranches de Vie")
      expect(response.body).to include("Tranches de Vie (Pizza Party)")
      payment = stay.reload.party_reservations.first.payment
      expect(response.body).not_to include(stay_payment_path(stay, payment))
    end
  end
end
