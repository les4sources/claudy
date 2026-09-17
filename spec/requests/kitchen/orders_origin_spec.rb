require "rails_helper"

# Epic #321, phase 2, décision 3 — d'où vient la demande.
#
# Malau propose souvent un repas au groupe de sa propre initiative, avant que le
# client ait rien demandé. Trois semaines plus tard, devant la ligne, elle ne
# sait plus qui relancer. L'origine répond à cette question, et à elle seule.
RSpec.describe "Cuisine — origine de la demande (epic #321, phase 2)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-kitchen-origin@les4sources.be", password: "password123") }
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph-origin@les4sources.be", status: "active") }
  before { sign_in user }

  let(:customer) { Customer.create!(email: "origin-test@example.com", first_name: "Groupe", last_name: "Origine") }
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "pending",
                 arrival_date: Date.current + 20, departure_date: Date.current + 22)
  end

  def line(**attrs)
    stay.meal_orders.create!({ kind: "repas", people: 10, date: Date.current + 20 }.merge(attrs))
  end

  describe "le modèle" do
    it "vaut « client » par défaut, sans qu'on ait rien dit" do
      expect(line.origin).to eq("client")
    end

    it "refuse une origine inconnue" do
      expect(stay.meal_orders.new(kind: "repas", people: 4, origin: "telepathie")).not_to be_valid
    end

    it "porte son libellé long et son libellé court" do
      expect(line(origin: "reception").origin_label).to eq("Proposée par l'accueil")
      expect(line(origin: "client").origin_short_label).to eq("Client")
    end
  end

  describe "le funnel public" do
    it "pose explicitement « client » sur les repas d'une réservation" do
      arrival = Date.current + 40
      draft = Reservations::Draft.new(
        arrival_date: arrival.iso8601, departure_date: (arrival + 2).iso8601,
        first_name: "Camille", last_name: "Martin",
        email: "camille-origin@example.com", phone: "+32470112233",
        meals: [{ kind: "repas", people: 8 }]
      )
      builder = Reservations::Builder.new(draft: draft)
      expect(builder.run).to be(true)

      expect(builder.stay.meal_orders.map(&:origin)).to all(eq("client"))
    end
  end

  describe "le formulaire de saisie manuelle" do
    it "présélectionne « Proposée par l'accueil »" do
      get new_kitchen_order_path

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      checked = doc.css("input[name='meal_order[origin]'][checked]").map { |i| i["value"] }
      expect(checked).to eq(["reception"])
    end

    it "enregistre l'origine choisie à la création d'une ligne unique" do
      post kitchen_orders_path, params: {
        meal_order: { stay_id: stay.id, kind: "apero", people: 6,
                      date: (Date.current + 21).iso8601, status: "requested",
                      origin: "client" }
      }

      expect(MealOrder.last.origin).to eq("client")
    end

    it "retombe sur « accueil » si l'origine postée est forgée" do
      post kitchen_orders_path, params: {
        meal_order: { stay_id: stay.id, kind: "apero", people: 6,
                      date: (Date.current + 21).iso8601, status: "requested" },
        prestations: { "0" => { kind: "apero", people: "6", status: "requested",
                                date: (Date.current + 21).iso8601, moment: "soir" } }
      }

      expect(MealOrder.last.origin).to eq("reception")
    end

    it "applique une seule origine à toutes les prestations d'une même saisie" do
      post kitchen_orders_path, params: {
        meal_order: { stay_id: stay.id, origin: "reception" },
        prestations: {
          "0" => { kind: "apero", people: "6", status: "requested",
                   date: (Date.current + 21).iso8601, moment: "soir" },
          "1" => { kind: "buffet_vege", people: "12", status: "requested",
                   date: (Date.current + 22).iso8601, moment: "midi" }
        }
      }

      expect(stay.meal_orders.count).to eq(2)
      expect(stay.meal_orders.map(&:origin).uniq).to eq(["reception"])
    end

    it "laisse modifier l'origine d'une demande existante" do
      order = line(origin: "client")

      patch kitchen_order_path(order), params: {
        meal_order: { kind: order.kind, people: order.people, status: order.status,
                      origin: "reception" }
      }

      expect(order.reload.origin).to eq("reception")
    end
  end

  describe "la table" do
    it "affiche la pastille d'origine avec sa phrase entière en title" do
      line(origin: "reception")

      get kitchen_orders_path(view: :kitchen)

      badge = Nokogiri::HTML(response.body).css("tr[id^=order-] span[title]")
                      .find { |span| span.text.strip == "Accueil" }
      expect(badge).to be_present
      expect(badge["title"]).to eq("Proposée par l'accueil")
    end
  end

  describe "le filtre par origine" do
    def ids_on(**params)
      get kitchen_orders_path(**params)
      expect(response).to have_http_status(:ok)
      Nokogiri::HTML(response.body).css("tr[id^=order-]").map { |tr| tr["id"].delete_prefix("order-").to_i }
    end

    it "ne montre que l'origine demandée dans les vues de travail" do
      from_client    = line(origin: "client")
      from_reception = line(origin: "reception")

      expect(ids_on(view: :kitchen)).to contain_exactly(from_client.id, from_reception.id)
      expect(ids_on(view: :kitchen, origin: "client")).to eq([from_client.id])
      expect(ids_on(view: :kitchen, origin: "reception")).to eq([from_reception.id])
    end

    def origin_filter_links
      Nokogiri::HTML(response.body).css("a[href*='origin=']").map { |a| a.text.strip }
    end

    it "propose le filtre dans les vues Cuisine, Accueil et Info, nulle part ailleurs" do
      %i[kitchen reception info].each do |view|
        get kitchen_orders_path(view: view)
        expect(origin_filter_links).to include("Demande du client"), "filtre attendu dans #{view}"
      end

      get kitchen_orders_path(view: :past)
      expect(origin_filter_links).to be_empty
    end

    it "ignore un paramètre d'origine resté dans l'URL d'une vue sans sélecteur" do
      from_client = line(origin: "client", date: Date.current - 3)

      get kitchen_orders_path(view: :past, origin: "reception")

      ids = Nokogiri::HTML(response.body).css("tr[id^=order-]").map { |tr| tr["id"].delete_prefix("order-").to_i }
      expect(ids).to include(from_client.id)
    end
  end
end
