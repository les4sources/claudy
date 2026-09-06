require "rails_helper"

# Page Cuisine (epic #219, phase 3) — le tableau de Malau dans Claudy.
RSpec.describe "Cuisine — page et actions", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)  { User.create!(email: "admin-kitchen-orders@les4sources.be", password: "password123") }
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be", status: "active") }
  let!(:michael) { Human.create!(name: "Michael", email: "michael@les4sources.be", status: "active") }
  before { sign_in user }

  let(:customer) { Customer.create!(email: "malau-test@example.com", first_name: "Groupe", last_name: "Test") }
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "pending",
                 arrival_date: Date.current + 20, departure_date: Date.current + 22)
  end

  def line(**attrs)
    stay.meal_orders.create!({ kind: "repas", people: 10, date: Date.current + 20 }.merge(attrs))
  end

  describe "GET /kitchen/orders" do
    it "range chaque demande dans une seule section" do
      todo      = line
      upcoming  = line(validation: "accepted", status: "confirmed", date: Date.current + 21)
      inquiry   = line(status: "inquiry", validation: "accepted", date: Date.current + 22)
      archived  = line(validation: "accepted", date: Date.current - 5)
      cancelled = line(status: "cancelled", cancellation_reason: "Groupe annulé")

      get kitchen_orders_path

      expect(response).to have_http_status(:ok)
      expect(CGI.unescapeHTML(response.body))
        .to include("À traiter", "À venir", "Demandes d'info", "Archives", "Annulés et refusés")
      # Chaque ligne existe, et la page les groupe sous le nom du client.
      [todo, upcoming, inquiry, archived, cancelled].each { |o| expect(o.reload).to be_persisted }
      expect(response.body).to include("Groupe Test")
    end

    it "filtre par famille et par responsable" do
      repas  = line(responsible_human: steph)
      buffet = line(kind: "buffet_vege", responsible_human: michael, notes: "buffet de michael")

      get kitchen_orders_path(family: "buffet")
      expect(response.body).to include("buffet de michael")

      get kitchen_orders_path(family: "repas")
      expect(response.body).not_to include("buffet de michael")

      get kitchen_orders_path(responsible_human_id: michael.id)
      expect(response.body).to include("buffet de michael")

      get kitchen_orders_path(responsible_human_id: steph.id)
      expect(response.body).not_to include("buffet de michael")
      expect(repas.reload.responsible_human).to eq(steph)
    end
  end

  describe "POST /kitchen/orders" do
    def create_params(**attrs)
      { meal_order: { stay_id: stay.id, kind: "repas", moment: "soir", date: (Date.current + 20).iso8601,
                      people: 12, status: "requested", notes: "sans porc" }.merge(attrs) }
    end

    it "crée une demande de repas qui reste à valider, même avec un responsable" do
      expect { post kitchen_orders_path, params: create_params(responsible_human_id: steph.id) }
        .to change(MealOrder, :count).by(1)

      order = MealOrder.order(:created_at).last
      expect(order.responsible_human).to eq(steph)
      expect(order.validation).to eq("pending") # seule Stéphanie décide de sa disponibilité
      expect(order.price_cents).to eq(18_000)
    end

    it "accepte d'emblée un buffet dont quelqu'un se charge" do
      post kitchen_orders_path, params: create_params(kind: "buffet_vege", responsible_human_id: michael.id)

      order = MealOrder.order(:created_at).last
      expect(order.validation).to eq("accepted")
      expect(order.validated_at).to be_present
    end

    it "laisse un buffet sans responsable en attente" do
      post kitchen_orders_path, params: create_params(kind: "buffet_vege", responsible_human_id: "")

      expect(MealOrder.order(:created_at).last.validation).to eq("pending")
    end

    it "applique le prix unitaire saisi en euros" do
      post kitchen_orders_path, params: create_params(unit_price: "22,50")

      order = MealOrder.order(:created_at).last
      expect(order.unit_price_cents).to eq(2_250)
      expect(order.price_cents).to eq(27_000)
    end
  end

  describe "PATCH /kitchen/orders/:id" do
    it "remet la validation en attente et le dit quand la prestation change" do
      order = line(validation: "accepted", validated_at: Time.current, responsible_human: steph)

      patch kitchen_order_path(order), params: { meal_order: { people: 20 } }

      expect(order.reload.validation).to eq("pending")
      expect(flash[:notice]).to include("revalider")
    end

    it "ne dit rien de tel quand seules les notes changent" do
      order = line(validation: "accepted", validated_at: Time.current)

      patch kitchen_order_path(order), params: { meal_order: { notes: "table ronde" } }

      expect(order.reload.validation).to eq("accepted")
      expect(flash[:notice]).not_to include("revalider")
    end

    it "enregistre les coûts réels saisis en euros" do
      order = line

      patch kitchen_order_path(order), params: { meal_order: { cost: "42,10", cost_notes: "courses" } }

      expect(order.reload.cost_cents).to eq(4_210)
      expect(order.cost_notes).to eq("courses")
    end
  end

  describe "PATCH /kitchen/orders/:id/assign" do
    it "confie la demande et vaut acceptation pour un buffet" do
      order = line(kind: "buffet_vege")

      patch assign_kitchen_order_path(order), params: { human_id: michael.id }

      expect(order.reload.responsible_human).to eq(michael)
      expect(order.validation).to eq("accepted")
    end

    it "confie un repas sans court-circuiter la validation de Stéphanie" do
      order = line

      patch assign_kitchen_order_path(order), params: { human_id: steph.id }

      expect(order.reload.responsible_human).to eq(steph)
      expect(order.validation).to eq("pending")
    end

    it "refuse d'assigner quand personne n'est nommé et que le compte n'a pas de membre" do
      order = line

      patch assign_kitchen_order_path(order)

      expect(order.reload.responsible_human).to be_nil
      expect(flash[:alert]).to include("Choisissez qui s'en charge")
    end
  end

  describe "PATCH /kitchen/orders/:id/status" do
    it "passe une demande d'info en ferme puis en confirmé" do
      order = line(status: "inquiry")

      patch status_kitchen_order_path(order), params: { status: "requested" }
      expect(order.reload.status).to eq("requested")

      patch status_kitchen_order_path(order), params: { status: "confirmed" }
      expect(order.reload.status).to eq("confirmed")
    end

    it "exige un motif pour annuler" do
      order = line

      patch status_kitchen_order_path(order), params: { status: "cancelled" }
      expect(order.reload.status).not_to eq("cancelled")
      expect(flash[:alert]).to include("motif")

      patch status_kitchen_order_path(order), params: { status: "cancelled", cancellation_reason: "Groupe annulé" }
      expect(order.reload.status).to eq("cancelled")
      expect(order.cancellation_reason).to eq("Groupe annulé")
    end
  end

  describe "GET /kitchen/orders/new et /:id/edit" do
    it "présélectionne le séjour et le responsable par défaut de la famille" do
      Setting.set("kitchen.repas.default_human_id", steph.id)

      get new_kitchen_order_path(stay_id: stay.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Groupe Test")
      expect(response.body).to include("selected=\"selected\" value=\"#{steph.id}\"")
    end

    it "affiche l'historique de la ligne" do
      order = line
      order.update!(people: 14)

      get edit_kitchen_order_path(order)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Historique", "Convives")
    end
  end

  describe "fiche séjour" do
    it "montre le bloc Cuisine et le lien d'ajout" do
      line(notes: "deux véganes")

      get stay_path(stay)

      expect(response.body).to include("Cuisine", "deux véganes")
      expect(response.body).to include("/kitchen/orders/new?stay_id=#{stay.id}")
    end
  end
end
