require "rails_helper"

# Issue #315 — le cycle complet d'une demande née avant son séjour :
# création sans séjour → visible dans la liste avec son texte libre →
# validation par la cuisine → rattachement → facturable et présente sur le séjour.
RSpec.describe "Cuisine — une demande sans séjour", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-kitchen-orphan@les4sources.be", password: "password123") }
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph-orphan@les4sources.be", status: "active") }
  before { sign_in user }

  let(:customer) { Customer.create!(email: "orphan-req@example.com", first_name: "Groupe", last_name: "Tardif") }
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "pending",
                 arrival_date: Date.current + 20, departure_date: Date.current + 22)
  end

  def orphan(**attrs)
    MealOrder.create!({ kind: "repas", people: 10, date: Date.current + 20,
                        status: "requested", contact_label: "École de Godinne",
                        skip_notifications: true }.merge(attrs))
  end

  describe "création" do
    it "crée une demande sans séjour, avec le seul texte libre" do
      expect {
        post kitchen_orders_path, params: {
          meal_order: { contact_label: "École de Godinne", kind: "repas", moment: "midi",
                        date: (Date.current + 20).iso8601, people: 12, status: "requested" }
        }
      }.to change(MealOrder, :count).by(1)

      order = MealOrder.order(:id).last
      expect(order.stay_id).to be_nil
      expect(order.contact_label).to eq("École de Godinne")
      expect(response).to redirect_to(kitchen_orders_path)
    end

    it "refuse une demande sans séjour NI texte libre" do
      expect {
        post kitchen_orders_path, params: {
          meal_order: { kind: "repas", moment: "midi", date: (Date.current + 20).iso8601,
                        people: 12, status: "requested" }
        }
      }.not_to change(MealOrder, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "crée une saisie multi-prestations sans séjour" do
      expect {
        post kitchen_orders_path, params: {
          meal_order: { contact_label: "Anniversaire Dupont" },
          prestations: { "0" => { kind: "apero", people: "8", status: "requested",
                                  date: (Date.current + 25).iso8601, moment: "soir" } }
        }
      }.to change(MealOrder, :count).by(1)

      order = MealOrder.order(:id).last
      expect(order.stay_id).to be_nil
      expect(order.contact_label).to eq("Anniversaire Dupont")
    end
  end

  describe "affichage" do
    it "montre le texte libre et la pastille « sans séjour » dans la liste" do
      orphan

      get kitchen_orders_path(view: :all)

      body = CGI.unescapeHTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(body).to include("École de Godinne")
      expect(body).to include("sans séjour")
    end

    it "ne propose pas « Ouvrir le séjour » sur une demande orpheline" do
      order = orphan

      get kitchen_orders_path(view: :all)

      row = Nokogiri::HTML(response.body).css("tr#order-#{order.id}").to_html
      expect(row).not_to include("Ouvrir le séjour")
      expect(row).to include("Rattacher à un séjour")
    end

    it "groupe chaque texte libre à part" do
      orphan(contact_label: "École de Godinne")
      orphan(contact_label: "Anniversaire Dupont")

      get kitchen_orders_path(view: :all)

      body = CGI.unescapeHTML(response.body)
      expect(body).to include("École de Godinne", "Anniversaire Dupont")
    end
  end

  describe "modification" do
    it "permet de corriger le texte libre" do
      order = orphan

      patch kitchen_order_path(order), params: {
        meal_order: { kind: "repas", people: 10, contact_label: "École de Yvoir" }
      }

      expect(order.reload.contact_label).to eq("École de Yvoir")
    end
  end

  describe "rattachement" do
    it "rattache la demande au séjour et la rend facturable" do
      order = orphan

      patch attach_kitchen_order_path(order), params: { stay_id: stay.id }

      order.reload
      expect(order.stay).to eq(stay)
      expect(order).to be_billable
      # Le texte libre survit : c'est la trace du premier contact.
      expect(order.contact_label).to eq("École de Godinne")
    end

    it "fait apparaître la demande sur la fiche du séjour" do
      order = orphan(unit_price_cents: 2_000, people: 5)
      patch attach_kitchen_order_path(order), params: { stay_id: stay.id }

      get stay_path(stay)

      expect(response).to have_http_status(:ok)
      expect(stay.reload.meal_orders.billable.sum(:price_cents)).to eq(10_000)
    end

    it "refuse de rattacher une demande qui a déjà un séjour" do
      other = Stay.create!(customer: customer, source: "manual", status: "pending",
                           arrival_date: Date.current + 50, departure_date: Date.current + 51)
      order = MealOrder.create!(kind: "repas", people: 4, stay: stay, skip_notifications: true)

      patch attach_kitchen_order_path(order), params: { stay_id: other.id }

      expect(order.reload.stay).to eq(stay)
      expect(flash[:alert]).to be_present
    end

    it "refuse un rattachement sans séjour choisi" do
      order = orphan

      patch attach_kitchen_order_path(order), params: { stay_id: "" }

      expect(order.reload.stay_id).to be_nil
      expect(flash[:alert]).to be_present
    end
  end

  describe "validation par la cuisine" do
    it "accepte une demande orpheline depuis l'écran Cuisine" do
      order = orphan

      patch accept_kitchen_order_path(order)

      expect(order.reload.validation).to eq("accepted")
    end

    it "accepte une demande orpheline par le lien signé" do
      order = orphan

      get kitchen_validation_path(order.validation_token)
      expect(response).to have_http_status(:ok)
      expect(CGI.unescapeHTML(response.body)).to include("École de Godinne")

      post kitchen_validation_confirm_path(order.validation_token)
      expect(order.reload.validation).to eq("accepted")
    end

    it "mène au formulaire de motif, qui se rend sans séjour" do
      order = orphan

      get kitchen_validation_refuse_path(order.validation_token)
      expect(response).to redirect_to(new_refusal_kitchen_order_path(order))

      get new_refusal_kitchen_order_path(order)
      expect(response).to have_http_status(:ok)
      expect(CGI.unescapeHTML(response.body)).to include("École de Godinne")
    end
  end
end
