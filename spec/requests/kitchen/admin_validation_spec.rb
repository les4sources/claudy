require "rails_helper"

# Canal ADMIN de la validation (epic #219, phase 4). Les comptes sont partagés :
# n'importe quel utilisateur connecté répond pour la cuisine.
RSpec.describe "Cuisine — validation depuis la page", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-valid@les4sources.be", password: "password123") }
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be", status: "active") }
  before { sign_in user }

  let(:customer) { Customer.create!(email: "client-admin@example.com", first_name: "Groupe", last_name: "Admin") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "pending") }
  let(:order) do
    stay.meal_orders.create!(kind: "repas", people: 10, date: Date.current + 20, responsible_human: steph)
  end

  it "accepte depuis la page" do
    patch accept_kitchen_order_path(order)

    expect(order.reload).to be_accepted
    expect(order.validated_at).to be_present
  end

  it "refuse avec un motif, et prévient la coordination" do
    ActionMailer::Base.deliveries.clear

    patch refuse_kitchen_order_path(order), params: { meal_order: { refusal_reason: "Je suis en congé" } }

    expect(order.reload).to be_refused
    expect(order.refusal_reason).to eq("Je suis en congé")
    expect(ActionMailer::Base.deliveries.last.to).to eq([Kitchen::Config.coordinator_email])
  end

  it "refuse de refuser sans motif" do
    patch refuse_kitchen_order_path(order), params: { meal_order: { refusal_reason: "" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(order.reload).to be_pending
  end

  it "propose les deux réponses sur une ligne à valider" do
    order

    get kitchen_orders_path

    expect(response.body).to include("C'est possible".gsub("'", "&#39;"))
    expect(response.body).to include(new_refusal_kitchen_order_path(order))
  end
end
