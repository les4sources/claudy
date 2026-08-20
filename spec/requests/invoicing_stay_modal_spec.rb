require "rails_helper"

# Facturation (/invoicing) — le clic sur un séjour OUVRE LA MODALE (Michael
# 2026-08-20). Le lien partait sur le formulaire d'édition, alors qu'on veut
# d'abord LIRE le séjour depuis la file. La modale porte son propre lien
# « Modifier la composition → » pour qui doit corriger.
RSpec.describe "Facturation — modale séjour", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "factu-modale@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:customer) do
    Customer.create!(email: "factu@example.com", first_name: "Fanny", last_name: "Facture")
  end

  def stay
    @stay ||= Stay.create!(customer: customer, source: "manual", status: "confirmed",
                           arrival_date: Date.today + 3, departure_date: Date.today + 5)
  end

  def booking(invoice_status:, tier: nil, price_cents: 15_000)
    Booking.create!(firstname: "T", group_name: "Chorale de Dinant", adults: 2,
                    from_date: Date.today + 3, to_date: Date.today + 5,
                    status: "confirmed", invoice_status: invoice_status,
                    price_cents: price_cents, tier: tier, stay: stay)
  end

  it "pointe la file « à fournir » sur la modale, pas sur le formulaire d'édition" do
    booking(invoice_status: "requested")

    get invoicing_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(href="#{stay_path(stay)}"))
    expect(response.body).not_to include(%(href="#{edit_stay_path(stay)}"))
  end

  it "câble le lien sur le contrôleur Stimulus qui ouvre la fiche" do
    booking(invoice_status: "requested")

    get invoicing_path

    expect(response.body).to include('data-action="stay-details#open"')
    expect(response.body).to include('data-controller="stay-details"')
    expect(response.body).to include('data-stay-details-target="dialog"')
    expect(response.body).to include('data-stay-details-target="content"')
  end

  it "applique la même règle au bloc « sans tarif défini »" do
    booking(invoice_status: "on", tier: Invoicing::Queue::UNDEFINED_TIER, price_cents: 0)

    get invoicing_path

    expect(response.body).to include("sans tarif défini")
    expect(response.body).to include(%(href="#{stay_path(stay)}"))
    expect(response.body).not_to include(%(href="#{edit_stay_path(stay)}"))
  end
end
