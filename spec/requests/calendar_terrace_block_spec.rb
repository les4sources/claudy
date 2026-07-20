require "rails_helper"

# Terrasse au calendrier — chip distincte « 🪑 Terrasse · N pers. » (PAS ⛺️) dans
# le bloc séjour unifié, et surtout PAS de 💤 : la terrasse est une occupation de
# JOUR, jamais une nuitée (décision Michael, 2026-07-20).
RSpec.describe "Calendrier — bloc terrasse", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-terrasse@les4sources.be", password: "password123") }
  before { sign_in user }

  it "rend une chip 🪑 Terrasse, sans ⛺️ ni 💤, sur un séjour terrasse-seule" do
    day = Date.today.next_occurring(:tuesday)

    customer = Customers::UpsertByEmail.call(email: "bbq@example.com", attrs: { first_name: "BBQ" })
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: day, departure_date: day + 1)
    terrace = CampingBooking.create!(firstname: "BBQ", group_name: "Rando BBQ",
                                     from_date: day, to_date: day + 1, people: 8,
                                     status: "confirmed", kind: "terrasse",
                                     price_cents: 2_000)
    StayItem.create!(stay: stay, bookable: terrace)

    get "/"
    expect(response).to have_http_status(:ok)

    block = response.body[/data-stay-id="#{stay.id}".*?<\/div>/m]
    full  = response.body
    # Chip terrasse présente…
    expect(full).to include("🪑 Terrasse · 8 pers.")
    # …et un séjour terrasse-seule ne dort PAS sur place (pas de 💤) ni ⛺️.
    expect(block).not_to include("💤")
    expect(full).not_to include("⛺️ 8 pers.")
    # UN seul bloc pour ce séjour.
    expect(full.scan("data-stay-id=\"#{stay.id}\"").size).to eq(1)
  end
end

# Icônes de composition de la fiche client : 🪑 pour la terrasse (distincte de ⛺).
RSpec.describe StaysCompositionHelper, "terrasse", type: :helper do
  it "affiche 🪑 pour une terrasse et jamais ⛺ à sa place" do
    day = Date.today + 10
    customer = Customers::UpsertByEmail.call(email: "fiche@example.com", attrs: { first_name: "Fiche" })
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: day, departure_date: day + 1)
    terrace = CampingBooking.create!(firstname: "Fiche", from_date: day, to_date: day + 1,
                                     people: 4, status: "confirmed", kind: "terrasse",
                                     price_cents: 1_000)
    StayItem.create!(stay: stay, bookable: terrace)

    html = helper.stay_composition_icons(stay.reload).to_s
    expect(html).to include("🪑")
    expect(html).not_to include("⛺")
  end
end
