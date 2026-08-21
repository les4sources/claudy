require "rails_helper"

# Nom affiché sur le calendrier (Michael 2026-08-21). Le bloc séjour titrait avec
# les colonnes brutes du réservable d'origine (`group_name` / `firstname
# lastname`), figées à la création : un séjour réassigné à un autre client
# affichait au calendrier le nom du formulaire de réservation pendant que sa
# modale affichait le vrai client. Le titre vient désormais du séjour lui-même —
# la MÊME source que la modale (`StayDecorator#display_name`).
RSpec.describe "Calendrier — nom du client sur le bloc séjour", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-nom@les4sources.be", password: "password123") }
  let(:space) { Space.create!(name: "Cuisine professionnelle", code: "CUI", capacity: 10) }

  before { sign_in user }

  it "titre avec le CLIENT du séjour, pas le nom porté par la réservation d'origine" do
    date = Date.today.next_occurring(:friday)

    customer = Customers::UpsertByEmail.call(
      email: "asbl@example.com",
      attrs: { customer_type: "organization", organization_name: "Association Cliente" }
    )
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: date, departure_date: date)

    # La réservation garde le nom saisi au formulaire : c'est lui qui s'affichait.
    space_booking = SpaceBooking.create!(firstname: "Prénom", lastname: "Formulaire",
                                         from_date: date, to_date: date, status: "confirmed")
    SpaceReservation.create!(space: space, space_booking: space_booking, date: date)
    StayItem.create!(stay: stay, bookable: space_booking)

    get "/", params: { date: date.to_s }

    expect(response).to have_http_status(:ok)
    block = response.body[/<div[^>]*data-stay-id="#{stay.id}".*?<\/div>/m]
    expect(block).to include("Association Cliente")
    expect(block).not_to include("Prénom Formulaire")
    # La chip du mode fusion nomme le séjour comme la carte.
    expect(response.body).to include("data-stay-label=\"Association Cliente\"")
  end

  it "garde le nom de la réservation d'origine sur un séjour du client FOURRE-TOUT" do
    date = Date.today.next_occurring(:friday)

    catch_all = Customers::UpsertByEmail.call(
      email: Customer::CATCH_ALL_EMAIL,
      attrs: { first_name: "Client", last_name: "Les 4 Sources" }
    )
    stay = Stay.create!(customer: catch_all, source: "manual", status: "confirmed",
                        arrival_date: date, departure_date: date)

    space_booking = SpaceBooking.create!(group_name: "Camp louveteaux", firstname: "Chef",
                                         from_date: date, to_date: date, status: "confirmed")
    SpaceReservation.create!(space: space, space_booking: space_booking, date: date)
    StayItem.create!(stay: stay, bookable: space_booking)

    get "/", params: { date: date.to_s }

    expect(response).to have_http_status(:ok)
    block = response.body[/<div[^>]*data-stay-id="#{stay.id}".*?<\/div>/m]
    expect(block).to include("Camp louveteaux")
    expect(block).not_to include("Client Les 4 Sources")
  end
end
