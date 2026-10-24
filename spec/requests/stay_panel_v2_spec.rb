require "rails_helper"

# Fiche séjour en panneau, nouvelle interface (redesign, Michael 2026-10-24) :
# qui et quand, l'étape du dossier, les faits, l'argent et la composition, une
# seule action principale en pied selon le statut. L'ancienne interface garde
# la modale en deux colonnes.
RSpec.describe "Fiche séjour en panneau", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "panneau-sejour@les4sources.be", password: "password123", new_interface: true) }
  let(:customer) do
    Customer.create!(email: "claire.dubois@example.com", first_name: "Claire", last_name: "Dubois", phone: "0478552109")
  end
  let(:lodging) { Lodging.create!(name: "La Chevêche", available_for_bookings: true) }

  before { sign_in user }

  def stay_with_lodging(status: "pre_confirmed")
    stay = Stay.create!(customer: customer, source: "manual", status: status,
                        arrival_date: Date.today + 3, departure_date: Date.today + 6)
    booking = Booking.create!(firstname: "Claire", lastname: "Dubois", from_date: stay.arrival_date, to_date: stay.departure_date,
                              adults: 2, children: 4, babies: 0, status: "confirmed", booking_type: "lodging", lodging: lodging)
    StayItem.create!(stay: stay, bookable: booking)
    stay
  end

  def panel
    Nokogiri::HTML(response.body).at_css("#stay-details-#{@stay.id}.ui-sd")
  end

  it "montre l'étape du dossier, les faits et le moyen de joindre le client" do
    @stay = stay_with_lodging

    get stay_path(@stay, modal: 1)

    expect(response).to have_http_status(:ok)
    expect(panel).to be_present
    expect(panel.at_css(".ui-sd-over").text).to include("Séjour ##{@stay.id}", "La Chevêche")
    expect(panel.at_css(".ui-sd-when").text).to include("3 nuits", "6 personnes")
    expect(panel.at_css(".ui-sd-steps [aria-current='step']").text).to include("Pré-confirmé", "acompte demandé")
    expect(panel.at_css(".ui-sd-facts").text).to include("2 adultes, 4 enfants", "Claire Dubois")
    expect(panel.at_css(".ui-sd-contact a[href='tel:0478552109']")).to be_present
    expect(panel.at_css(".ui-sd-contact a[href='mailto:claire.dubois@example.com']")).to be_present
    expect(panel.at_css(".ui-sd-items").text).to include("La Chevêche")
    # Le bloc Argent garde sa frame : les activités et la party la rafraîchissent.
    expect(panel.at_css("turbo-frame#stay_#{@stay.id}_payments .ui-sd-money")).to be_present
  end

  it "met une seule action principale en pied, selon le statut" do
    @stay = stay_with_lodging(status: "pending")
    get stay_path(@stay, modal: 1)
    foot = panel.at_css(".ui-sd-foot")
    expect(foot.css(".ui-btn-p").map(&:text)).to eq(["Confirmer le séjour"])
    expect(foot.at_css(".ui-sd-hint").text).to include("Claire Dubois")
    expect(foot.css(".ui-sd-menu-l").text).to include("Pré-confirmer", "Refuser la demande", "Annuler le séjour")

    @stay.update!(status: "canceled")
    get stay_path(@stay, modal: 1)
    expect(panel.at_css(".ui-sd-steps").text).to include("Annulé")
    expect(panel.css(".ui-sd-foot .ui-btn-p").map { |b| b["value"].presence || b.text }).to eq(["Réactiver le séjour"])
  end

  it "garde la modale en deux colonnes dans l'ancienne interface" do
    user.update!(new_interface: false)
    @stay = stay_with_lodging

    get stay_path(@stay, modal: 1)

    expect(response.body).to include("stay-details-#{@stay.id}", "Pré-confirmer").or include("Confirmer le séjour")
    expect(Nokogiri::HTML(response.body).at_css(".ui-sd")).to be_nil
  end
end
