require "rails_helper"

# Epic #234, Phase 1 — la grille « Espaces » du FUNNEL PUBLIC couvre elle aussi
# chaque jour du séjour, jour de départ inclus. Décision 7 de l'epic : même
# partial, même comportement en admin et au funnel — ce qui est corrigé d'un côté
# l'est de l'autre.
RSpec.describe "Public::Reservations — grille Espaces par jour (epic #234, Phase 1)", type: :request do
  include ActiveJob::TestHelper

  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre 1", level: 1)
    l
  end
  let!(:petite_salle) { Space.create!(name: "Petite Salle", code: "SAU", capacity: 1) }

  let(:lundi)    { (Date.today + 60).next_occurring(:monday) }
  let(:vendredi) { lundi + 4 }

  before do
    allow(StripeService.instance).to receive(:create_checkout_session)
      .and_return(OpenStruct.new(url: "https://checkout.stripe.test/session/x"))
  end

  def grille_espaces(body)
    Nokogiri::HTML(body)
      .css("table")
      .find { |t| t.at_css(%(input[name="reservation[space_slots][petite_salle][]"])) }
  end

  it "rend 5 colonnes « Jour » pour un séjour de 4 nuits" do
    post "/reservation/sejour", params: {
      reservation: { arrival_date: lundi.iso8601, departure_date: vendredi.iso8601, adults: 2 }
    }
    get "/reservation/composer"

    expect(response).to have_http_status(:ok)
    entetes = grille_espaces(response.body).css("thead th").map { |th| th.text.strip }

    expect(entetes.grep(/Jour \d/).size).to eq(5)
    expect(entetes.join).not_to include("Nuit")
    expect(entetes.last).to include("Ven #{vendredi.strftime('%-d/%-m')}")
    expect(entetes.join).to include("arrivée").and include("départ")
  end

  it "persiste la réservation du jour du DÉPART via le Builder" do
    perform_enqueued_jobs do
      post "/reservation/coordonnees", params: {
        reservation: {
          arrival_date: lundi.iso8601, departure_date: vendredi.iso8601,
          dogs_count: 0, first_name: "Groupe", last_name: "Semaine",
          email: "groupe-funnel@example.com", phone: "+32470111222",
          space_slots: { petite_salle: %w[journee journee journee journee journee] }
        }
      }
    end

    stay = Stay.last
    sb = stay.stay_items.map(&:bookable).grep(SpaceBooking).first
    expect(sb).to be_present
    expect(sb.space_reservations.map(&:date).sort).to eq((lundi..vendredi).to_a)
    expect(sb.space_reservations.find_by(date: vendredi).duration).to eq("day")
    # La demande reste `pending` : elle n'immobilise pas la salle tant que
    # l'équipe n'a pas confirmé (`Space#booked_on?` ne compte que le confirmé).
    expect(sb.status).to eq("pending")
    expect(petite_salle.reload.available_on?(vendredi)).to be(true)
  end
end
