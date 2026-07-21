require "rails_helper"

# Issue #133 — parcours client de la demande de modification.
RSpec.describe "Demande de modification de séjour (client)", type: :request do
  include ActiveJob::TestHelper

  let(:customer) { Customer.create!(first_name: "Ana", last_name: "Lopez", email: "ana@example.com") }
  let!(:lodging) { Lodging.find_or_create_by!(name: "La Hulotte") { |l| l.price_night_cents = 48_500 } }

  let(:arrival)   { Date.current + 10 }
  let(:departure) { Date.current + 12 }

  let(:stay) do
    s = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                     arrival_date: arrival, departure_date: departure,
                     total_amount_cents: 74_500)
    # Composition réelle : un Booking Hulotte sur les 2 nuits (74 500 = barème
    # 48 500 + 26 000) — la recote de la composition actuelle sert de point de
    # référence au delta (prix préservé).
    booking = Booking.create!(firstname: "Ana", lastname: "Lopez", email: "ana@example.com",
                              from_date: arrival, to_date: departure, adults: 2,
                              status: "confirmed", price_cents: 74_500, lodging: lodging)
    s.stay_items.create!(bookable: booking)
    s
  end

  before { ActionMailer::Base.deliveries.clear }

  def submit(params = {})
    post public_stay_change_requests_path(stay.token), params: {
      reservation: {
        lodging_id: lodging.id,
        arrival_date: arrival.to_s,
        departure_date: departure.to_s,
        lodging_night_ids: [lodging.id.to_s, lodging.id.to_s]
      }
    }.deep_merge(params)
  end

  describe "GET /sejour/:token/modification" do
    it "affiche le formulaire prérempli" do
      get new_public_stay_change_request_path(stay.token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Modifier mon séjour")
      expect(response.body).to include("Votre nouveau devis")
    end

    it "renvoie 404 sur un jeton inconnu" do
      get new_public_stay_change_request_path("jeton-bidon")
      expect(response).to have_http_status(:not_found)
    end

    it "refuse un séjour déjà parti" do
      past = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                          arrival_date: Date.current - 10, departure_date: Date.current - 8)

      get new_public_stay_change_request_path(past.token)

      expect(response).to redirect_to(public_stay_path(past.token))
      follow_redirect!
      expect(response.body).to include("ne peut plus être modifié")
    end
  end

  describe "POST /sejour/:token/modification/devis" do
    it "recalcule le nouveau total et le delta en Turbo Stream" do
      post public_stay_change_request_quote_path(stay.token),
           params: { reservation: { lodging_id: lodging.id,
                                    arrival_date: arrival.to_s,
                                    departure_date: departure.to_s,
                                    lodging_night_ids: [lodging.id.to_s, lodging.id.to_s] } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("change_request_delta")
      expect(response.body).to include("Nouveau total")
    end
  end

  describe "POST /sejour/:token/modification" do
    it "crée une demande PENDING sans jamais toucher au séjour" do
      expect { submit }.to change { stay.stay_change_requests.count }.by(1)

      change = stay.stay_change_requests.last
      expect(change).to be_pending
      # Le séjour est strictement inchangé.
      expect(stay.reload.total_amount_cents).to eq(74_500)
      expect(stay.arrival_date).to eq(arrival)
      expect(response).to redirect_to(public_stay_path(stay.token))
    end

    it "envoie un email à l'équipe et un accusé au client" do
      perform_enqueued_jobs { submit }

      recipients = ActionMailer::Base.deliveries.map(&:to).flatten
      expect(recipients).to include("sejours@les4sources.be")
      expect(recipients).to include("ana@example.com")
    end

    it "préserve un prix historique : formulaire intact → delta 0, nouveau total = prix négocié" do
      # Prix négocié AU-DESSUS du barème (74 500) : la demande ne recote pas le
      # séjour, elle applique le delta de composition au prix existant.
      stay.stay_items.first.bookable.update!(price_cents: 186_000)
      stay.update!(total_amount_cents: 186_000)

      submit

      change = stay.stay_change_requests.last
      expect(change.delta_cents).to eq(0)
      expect(change.new_total_cents).to eq(186_000)
    end

    it "calcule un delta positif quand le client agrandit son séjour" do
      submit(reservation: { departure_date: (departure + 1).to_s,
                            lodging_night_ids: [lodging.id.to_s] * 3 })

      expect(stay.stay_change_requests.last.delta_cents).to be > 0
    end

    it "exige l'IBAN et affiche la mention des 10 jours en cas de trop-perçu" do
      Payment.create!(stay: stay, amount_cents: 74_500, payment_method: "card", status: "paid")

      # Réduction à une seule nuit → nouveau total < déjà payé, sans IBAN.
      expect {
        submit(reservation: { departure_date: (arrival + 1).to_s,
                              lodging_night_ids: [lodging.id.to_s] })
      }.not_to change { stay.stay_change_requests.count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Le remboursement sera effectué dans les 10 jours qui suivent le séjour.")
    end

    it "accepte la réduction quand l'IBAN est fourni" do
      Payment.create!(stay: stay, amount_cents: 74_500, payment_method: "card", status: "paid")

      submit(reservation: { departure_date: (arrival + 1).to_s,
                            lodging_night_ids: [lodging.id.to_s] })
      # (la première tentative sans IBAN a échoué ci-dessus)
      post public_stay_change_requests_path(stay.token), params: {
        refund_iban: "BE68539007547034",
        reservation: { lodging_id: lodging.id, arrival_date: arrival.to_s,
                       departure_date: (arrival + 1).to_s,
                       lodging_night_ids: [lodging.id.to_s] }
      }

      change = stay.stay_change_requests.last
      expect(change.refund_iban).to eq("BE68539007547034")
      expect(change.delta_cents).to be < 0
    end

    it "refuse la demande quand l'hébergement n'est plus disponible" do
      # Indisponibilité posée à la main sur le gîte : la règle de dispo est la
      # MÊME que celle de la validation admin (Stays::LodgingAvailability).
      (arrival..departure).each { |date| lodging.unavailabilities.create!(date: date) }

      expect { submit }.not_to change { stay.stay_change_requests.count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("n'est plus disponible")
    end

    it "remplace la demande en attente précédente" do
      submit
      first = stay.stay_change_requests.last

      submit(reservation: { departure_date: (departure + 1).to_s,
                            lodging_night_ids: [lodging.id.to_s] * 3 })

      expect(stay.stay_change_requests.pending.count).to eq(1)
      expect(StayChangeRequest.where(id: first.id)).to be_empty
    end
  end

  describe "page /sejour/:token" do
    it "propose le bouton de modification sur un séjour à venir" do
      get public_stay_path(stay.token)
      expect(response.body).to include("Demander une modification")
    end

    it "ne le propose PAS sur un séjour terminé" do
      past = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                          arrival_date: Date.current - 10, departure_date: Date.current - 8)

      get public_stay_path(past.token)
      expect(response.body).not_to include("Demander une modification")
    end
  end
end
