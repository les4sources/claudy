require "rails_helper"

# Canal JETON de validation de la cuisine (epic #219, phase 4) : le lien de
# l'email, cliqué depuis n'importe où, sans compte pour accepter.
RSpec.describe "Cuisine — validation par lien", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:customer) { Customer.create!(email: "client-token@example.com", first_name: "Groupe", last_name: "Token") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "pending") }
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be", status: "active") }
  let(:order) do
    stay.meal_orders.create!(kind: "repas", people: 10, date: Date.current + 20, responsible_human: steph)
  end

  it "affiche la demande sans rien changer" do
    get kitchen_validation_path(order.validation_token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Repas (midi ou soir)")
    expect(order.reload).to be_pending # un GET ne mute jamais
  end

  it "accepte au POST, et deux clics ne changent rien de plus" do
    token = order.validation_token

    post kitchen_validation_confirm_path(token)
    expect(response).to have_http_status(:ok)
    expect(order.reload).to be_accepted
    validated_at = order.validated_at

    post kitchen_validation_confirm_path(token)
    expect(order.reload.validated_at).to eq(validated_at)
  end

  it "n'accepte pas une demande déjà annulée" do
    order.update!(status: "cancelled", cancellation_reason: "Groupe annulé")

    post kitchen_validation_confirm_path(order.validation_token)

    expect(order.reload).to be_pending
    expect(response.body).to include("annulée")
  end

  it "impose la connexion pour refuser, puis mène au formulaire de motif" do
    get kitchen_validation_refuse_path(order.validation_token)
    expect(response).to redirect_to(new_user_session_path)

    sign_in User.create!(email: "n-importe-qui@les4sources.be", password: "password123")
    get kitchen_validation_refuse_path(order.validation_token)
    expect(response).to redirect_to(new_refusal_kitchen_order_path(order))
  end

  it "rend une page dédiée sur un jeton invalide ou d'une autre portée" do
    get kitchen_validation_path("n-importe-quoi")
    expect(response).to have_http_status(:not_found)

    get kitchen_validation_path(order.signed_id(purpose: :autre_chose))
    expect(response).to have_http_status(:not_found)
  end
end
