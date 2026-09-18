require "rails_helper"

# Epic #321, phase 3 — l'onglet « Prochains services ».
#
# La question qu'on se pose en arrivant sur la page Cuisine, c'est « qu'est-ce
# qui va vraiment avoir lieu ». Pas « qu'est-ce qui reste à traiter » : ça, c'est
# « À venir ». Les deux ne font pas doublon.
RSpec.describe "Cuisine — onglet Prochains services (epic #321, phase 3)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-upcoming@les4sources.be", password: "password123") }
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph-upcoming@les4sources.be", status: "active") }
  let(:customer) { Customer.create!(email: "client-upcoming@example.com", first_name: "Groupe", last_name: "Scout") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "confirmed") }

  before { sign_in user }

  def order(**attrs)
    stay.meal_orders.create!({ kind: "repas", people: 10, responsible_human: steph }.merge(attrs))
  end

  it "s'ouvre par défaut, sans paramètre" do
    get kitchen_orders_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Prochains services")
  end

  describe "son filtre" do
    it "ne montre que ce qui est accepté, daté et à venir" do
      accepte  = order(date: Date.current + 5, validation: "accepted")
      en_attente = order(date: Date.current + 6, validation: "pending")
      refuse   = order(date: Date.current + 7, validation: "refused", refusal_reason: "Je suis en congé")
      annule   = order(date: Date.current + 8, validation: "accepted", status: "cancelled")
      sans_date = order(date: nil, validation: "accepted")

      get kitchen_orders_path(view: :upcoming)
      body = response.body

      expect(body).to include("order-#{accepte.id}")
      expect(body).not_to include("order-#{en_attente.id}")
      expect(body).not_to include("order-#{refuse.id}")
      expect(body).not_to include("order-#{annule.id}")
      expect(body).not_to include("order-#{sans_date.id}")
    end

    it "laisse le passé dehors" do
      passe = order(date: Date.current - 1, validation: "accepted")
      aujourdhui = order(date: Date.current, validation: "accepted")

      get kitchen_orders_path(view: :upcoming)
      expect(response.body).not_to include("order-#{passe.id}")
      expect(response.body).to include("order-#{aujourdhui.id}")
    end

    it "trie par date croissante" do
      tard = order(date: Date.current + 20, validation: "accepted")
      tot  = order(date: Date.current + 2, validation: "accepted")

      get kitchen_orders_path(view: :upcoming)
      expect(response.body.index("order-#{tot.id}")).to be < response.body.index("order-#{tard.id}")
    end
  end

  describe "les intertitres par jour" do
    it "cumule les convives du jour" do
      jour = Date.current + 9
      order(date: jour, moment: "midi", people: 18, validation: "accepted")
      order(date: jour, moment: "soir", people: 24, validation: "accepted")

      get kitchen_orders_path(view: :upcoming)
      expect(response.body).to include("42 convives")
      expect(response.body).to include("2 services")
      # Une seule majuscule, à l'initiale : « Jeudi 26 mars », pas « Jeudi 26 Mars ».
      expect(response.body).to include(I18n.l(jour, format: "%A %-d %B").capitalize)
    end

    it "n'apparaissent pas dans les autres onglets" do
      order(date: Date.current + 9, people: 18, validation: "accepted")
      get kitchen_orders_path(view: :all)
      expect(response.body).not_to include("convives")
    end
  end

  describe "le compteur de l'onglet" do
    it "suit la même règle que la liste" do
      order(date: Date.current + 5, validation: "accepted")
      order(date: Date.current + 6, validation: "accepted")
      order(date: Date.current + 7, validation: "pending")

      get kitchen_orders_path(view: :upcoming)
      expect(response.body).to match(/Prochains services.*?>\s*2\s*</m)
    end
  end

  describe "l'onglet « À venir »" do
    it "reste ce qu'il est : il montre aussi ce qui n'est pas encore accepté" do
      en_attente = order(date: Date.current + 6, validation: "pending")

      get kitchen_orders_path(view: :all)
      expect(response.body).to include("order-#{en_attente.id}")
    end
  end
end
