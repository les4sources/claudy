require "rails_helper"

# Epic #260, phase 3 — « la totale » telle qu'elle S'AFFICHE.
#
# Le calcul est fixé ailleurs (`spec/services/pricing/full_package_spec.rb`).
# Ici on vérifie le rendu : le devis du formulaire admin, la fiche séjour et la
# page client montrent bien UNE ligne, et pas deux lignes contradictoires.
RSpec.describe "Séjours — la totale à l'écran (epic #260, phase 3)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-totale@les4sources.be", password: "password123") }
  let!(:grand_duc) { Lodging.find_or_create_by!(name: "Le Grand-Duc") { |l| l.price_night_cents = 75_000 } }

  # Lundi 5 octobre 2026 → jeudi 8 : 3 nuits, haute saison, −10 % = 2 727 €.
  let(:arrivee) { Date.new(2026, 10, 5) }
  let(:depart)  { Date.new(2026, 10, 8) }

  before { sign_in user }

  def full_package_params(holes: {})
    days = (arrivee..depart).to_a
    slots = Pricing::FullPackage::REQUIRED_SPACES.to_h do |space|
      periods = days.each_with_index.map { |_, index| Array(holes[space]).include?(index) ? "" : "journee" }
      [space, periods]
    end

    { customer_mode: "new", arrival_date: arrivee.iso8601, departure_date: depart.iso8601,
      adults: 4, children: 0, dogs_count: 0,
      lodging_night_ids: [grand_duc.id.to_s] * 3,
      space_slots: slots }
  end

  def devis(params)
    post quote_stays_path, params: { stay: params }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    CGI.unescapeHTML(response.body)
  end

  it "montre UNE ligne « La totale » dans le devis du formulaire admin" do
    body = devis(full_package_params)

    expect(body).to include("La totale — Le Grand-Duc + les 2 salles + cuisine pro")
    expect(body).to include("3 nuits")
    expect(body).to include("haute saison")
    expect(body).to include("−10 %")
  end

  it "y garde la mention des espaces à 0 €, pour qu'on ne les croie pas oubliés" do
    expect(devis(full_package_params)).to include("compris dans la totale")
  end

  it "ne montre plus les lignes de salles à l'unité" do
    body = devis(full_package_params)

    expect(body).not_to include("Grande Salle —")
    expect(body).not_to include("Petite Salle —")
  end

  it "revient aux lignes à l'unité dès qu'une salle manque un jour" do
    body = devis(full_package_params(holes: { "cuisine_pro" => [2] }))

    expect(body).not_to include("La totale")
    expect(body).to include("Le Grand-Duc")
  end

  describe "la fiche séjour et la page client" do
    it "affichent la totale sur un séjour composé ainsi" do
      post stays_path, params: { stay: full_package_params.merge(
        new_customer: { first_name: "Groupe", last_name: "Totale", email: "totale@example.com",
                        phone: "0470111222" },
        status: "pending"
      ) }

      stay = Stay.order(:created_at).last
      expect(stay).to be_present
      expect(stay.total_amount_cents).to eq(272_700)

      get stay_path(stay)
      expect(response).to have_http_status(:ok)

      get public_stay_path(stay.token)
      expect(response).to have_http_status(:ok)
    end
  end
end
