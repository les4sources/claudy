require "rails_helper"

# Cuisine, nouvelle interface (redesign, Michael 2026-10-24) : la phrase du
# jour, les sections en tableau avec les mêmes gestes, demande d'info et à
# couvrir en cartes dans la vue Cuisine. L'ancienne interface est inchangée.
RSpec.describe "Cuisine — nouvelle interface", type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:steph) { Human.create!(name: "Stéphanie Leroy", email: "steph-v2@les4sources.be", status: "active") }
  let(:user) { User.create!(email: "cuisine-v2@les4sources.be", password: "password123", new_interface: true, human_id: steph.id) }
  let(:customer) { Customer.create!(email: "scouts-v2@example.com", first_name: "Scouts", last_name: "Namur") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "pending") }

  before { sign_in user }

  def page = Nokogiri::HTML(response.body)

  it "dit ce qui attend, propose oui ou non, et range le reste en cartes" do
    stay.meal_orders.create!(kind: "repas", moment: "soir", people: 24, date: Date.current, responsible_human: steph)
    MealOrder.create!(kind: "buffet_vege", moment: "midi", people: 14, date: Date.current, responsible_human: steph,
                      validation: "accepted", status: "confirmed", contact_label: "Yoga Ardennes")
    MealOrder.create!(kind: "gouter", moment: "gouter", people: 25, date: Date.current + 30, responsible_human: steph,
                      validation: "accepted", status: "inquiry", contact_label: "École de Purnode")

    get kitchen_orders_path(view: :kitchen)

    expect(response).to have_http_status(:ok)
    phrase = page.at_css(".ui-phrase").text.squish
    expect(phrase).to include("Stéphanie,", "1 demande", "attend ta réponse", "14 couverts prévus", "24 de plus si tu dis oui")

    to_validate = page.at_css("#section-to_validate")
    expect(to_validate.text).to include("Ce soir", "Scouts Namur", "Oui, je cuisine", "Pas possible")
    expect(to_validate.at_css("a[data-action='stay-details#open']")).to be_present
    expect(page.at_css("#section-planned .ui-kt-day").text).to include("Aujourd’hui", "14 couverts")
    expect(page.at_css("#section-inquiry .ui-kt-card").text).to include("École de Purnode", "Rien à préparer")
    # Le goûter compte parmi les repas.
    counts = page.css(".ui-ag-filters .ui-chip").to_h { |c| [c.children.first.text.squish, c.at_css(".ui-seg-n")&.text] }
    expect(counts).to include("Repas" => "2", "Buffets" => "1", "Apéros" => "0")
    # Les montants restent dans la vue Accueil.
    expect(response.body).not_to include("Total facturable")
  end

  it "garde les gestes de l'accueil et le total dans sa vue" do
    MealOrder.create!(kind: "repas", moment: "midi", people: 10, date: Date.current + 3, responsible_human: steph,
                      validation: "refused", refusal_reason: "En congé", contact_label: "Vero Telle")
    MealOrder.create!(kind: "repas", moment: "soir", people: 6, date: Date.current + 1, responsible_human: steph,
                      validation: "accepted", status: "confirmed", contact_label: "Famille Dubois")

    get kitchen_orders_path(view: :reception)

    expect(page.at_css(".ui-phrase").text.squish).to include("1 demande", "à relancer ou à couvrir")
    expect(page.at_css("#section-to_cover").text).to include("Vero Telle", "En congé", "Confier à…", "Annuler")
    expect(response.body).to include("Total facturable")

    get kitchen_orders_path(view: :out)
    expect(response).to have_http_status(:ok)
    expect(page.at_css(".ui-kt-arch [aria-current='page']").text).to include("Annulés")
  end

  it "laisse l'ancienne page à l'ancienne interface" do
    user.update!(new_interface: false)

    get kitchen_orders_path(view: :kitchen)

    expect(page.at_css(".ui-kt")).to be_nil
  end
end
