require "rails_helper"

# Amendement Michael 2026-07-21 (epic #126) : dès la livraison du domaine
# coworking, l'espace « Coworking » (Space capacity 3) sort du canal espaces —
# plus proposé nulle part à la composition ni à la réservation d'espaces. Son
# historique `SpaceBooking` reste intact et lisible.
RSpec.describe "Espace « Coworking » retiré du canal espaces", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  let!(:coworking_space) { Space.find_or_create_by!(code: "CWK") { |s| s.name = "Coworking"; s.capacity = 3 } }

  it "n'est plus listé dans le calendrier public de disponibilités" do
    expect(Public::CalendarsController::CALENDAR_SPACE_NAMES).not_to include("Coworking")

    get public_calendrier_hebergements_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(">Coworking<")
  end

  it "n'apparaît dans aucune grille de composition de séjour (admin ni public)" do
    sign_in user

    get new_stay_path
    expect(response).to have_http_status(:ok)
    # La navbar porte désormais une entrée « Coworking » (menu Accueil) : on
    # vérifie le corps de page HORS navigation.
    body_without_nav = response.body.gsub(%r{<nav.*?</nav>}m, "")
    expect(body_without_nav).not_to include("Coworking")

    get compose_grids_stays_path, params: { arrival_date: "2026-09-07", departure_date: "2026-09-10" }
    expect(response).to have_http_status(:ok)
    # La grille d'espaces est bornée aux espaces facturables du barème.
    expect(response.body).to include("Grande Salle")
    expect(response.body).not_to include("Coworking")
  end

  it "laisse l'historique SpaceBooking de l'espace intact" do
    booking = SpaceBooking.create!(firstname: "Ancien", group_name: "Ancien coworking",
                                   from_date: Date.new(2026, 3, 3), to_date: Date.new(2026, 3, 4),
                                   status: "confirmed")
    reservation = SpaceReservation.create!(space: coworking_space,
                                           space_booking: booking,
                                           date: Date.new(2026, 3, 3))

    expect(reservation.reload.space).to eq(coworking_space)
    expect(coworking_space.reload).to be_persisted
  end
end
