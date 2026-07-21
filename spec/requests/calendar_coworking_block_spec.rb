require "rails_helper"

# Epic #126, Phase 1 — le coworking apparaît au calendrier dans un bloc DISTINCT
# des séjours, et n'est jamais sélectionnable par le mode fusion.
RSpec.describe "Calendrier — bloc coworking", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-cwk@les4sources.be", password: "password123") }
  before { sign_in user }

  def pack_for(name)
    customer = Customer.create!(first_name: name, last_name: "Test",
                                email: "#{name.downcase}@example.com")
    CoworkingPack.create!(customer: customer, days_total: 5, payment_method: "card")
  end

  it "rend « 💻 Coworking 2/3 » avec les noms, sans data-stay-id" do
    day = Date.today.beginning_of_month.next_occurring(:tuesday)

    pack_for("Ana").coworking_reservations.create!(date: day)
    pack_for("Bruno").coworking_reservations.create!(date: day)

    get "/", params: { start_date: day.to_s }
    expect(response).to have_http_status(:ok)

    expect(response.body).to include("💻 Coworking 2/3")
    expect(response.body).to include("Ana")
    expect(response.body).to include("Bruno")

    # Le bloc coworking ne porte PAS de data-stay-id : le mode fusion (qui ne
    # sélectionne que ces blocs-là) ne peut donc jamais l'attraper.
    block = response.body[/data-coworking-day-entry="#{day}".*?💻 Coworking 2\/3/m]
    expect(block).to be_present
    expect(block).not_to include("data-stay-id")
  end

  it "n'affiche aucun bloc coworking un jour sans réservation" do
    day = Date.today.beginning_of_month.next_occurring(:tuesday)

    get "/", params: { start_date: day.to_s }

    expect(response.body).not_to include("💻 Coworking")
  end
end
