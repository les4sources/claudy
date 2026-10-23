require "rails_helper"

# Services annexes d'un séjour (Michael, 2026-10-23) : prêt d'un set de
# disc-golf… Une ligne libellé + montant, préremplie depuis /services, qui
# s'ajoute au total du séjour, prix imposé compris.
RSpec.describe "Fiche séjour — services annexes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-services@les4sources.be", password: "password123") }
  let(:customer) do
    Customer.create!(email: "scouts@example.com", customer_type: "organization", organization_name: "Scouts de Namur")
  end
  let(:stay) do
    Stay.create!(customer: customer, status: "confirmed",
                 arrival_date: Date.new(2026, 10, 8), departure_date: Date.new(2026, 10, 11))
  end
  let!(:discgolf) { Service.create!(name: "Prêt d'un set de disc-golf", price_cents: 1_500) }

  before { sign_in user }

  def euros(cents) = ApplicationController.helpers.humanized_money_with_symbol(Money.new(cents))

  it "propose le catalogue dans le bloc de la fiche séjour" do
    get stay_path(stay)

    expect(response.body).to include("Services annexes")
    expect(response.body).to include("Aucun service annexe.")
    expect(response.body).to include("Prêt d&#39;un set de disc-golf — #{euros(1_500)}")
    expect(response.body).to include('data-amount="15.00"')
  end

  it "ajoute une ligne au séjour et au total" do
    post stay_service_lines_path(stay), params: { stay_service_line: { service_id: discgolf.id, label: "Set de disc-golf (2 jours)", amount: "20,50" } }

    expect(response).to redirect_to(stay_path(stay))
    line = stay.service_lines.sole
    expect(line).to have_attributes(label: "Set de disc-golf (2 jours)", amount_cents: 2_050, service: discgolf)
    expect(stay.reload.total_amount_cents).to eq(2_050)

    get stay_path(stay)
    expect(response.body).to include("Set de disc-golf (2 jours)")
  end

  it "accepte une ligne libre, sans service du catalogue" do
    post stay_service_lines_path(stay), params: { stay_service_line: { label: "Location de vélos", amount: "40" } }

    expect(stay.service_lines.sole).to have_attributes(label: "Location de vélos", amount_cents: 4_000, service: nil)
  end

  it "refuse une ligne sans montant lisible" do
    post stay_service_lines_path(stay), params: { stay_service_line: { label: "Vélos", amount: "beaucoup" } }

    expect(flash[:alert]).to include("Montant illisible")
    expect(stay.service_lines).to be_empty
  end

  it "rafraîchit les blocs en Turbo Stream" do
    post stay_service_lines_path(stay), params: { stay_service_line: { service_id: discgolf.id, label: "", amount: "" } },
                                        as: :turbo_stream

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("stay_#{stay.id}_extras", "stay_#{stay.id}_payments")
    expect(stay.service_lines.sole).to have_attributes(label: discgolf.name, amount_cents: 1_500)
  end

  it "retire une ligne et la sort du total" do
    line = Stays::AddServiceLine.new(stay: stay).run!(label: "Vélos", amount_cents: 4_000)

    delete stay_service_line_path(stay, line)

    expect(stay.reload.service_lines).to be_empty
    expect(stay.total_amount_cents).to eq(0)
    expect(StayServiceLine.unscoped.find(line.id).deleted_at).to be_present
  end

  it "s'ajoute au prix imposé, comme le bar" do
    stay.update!(price_override_cents: 50_000)
    Stays::AddServiceLine.new(stay: stay).run!(label: "Disc-golf", amount_cents: 1_500)

    expect(stay.reload.total_amount_cents).to eq(51_500)
  end

  it "montre la ligne et son montant sur la page client" do
    stay.update!(price_override_cents: 50_000)
    Stays::AddServiceLine.new(stay: stay).run!(label: "Prêt d'un set de disc-golf", amount_cents: 1_500, service: discgolf)

    sign_out user
    get "/sejour/#{stay.token}"

    expect(response.body).to include("Prêt d&#39;un set de disc-golf")
    expect(response.body).to include(euros(1_500))
  end
end
