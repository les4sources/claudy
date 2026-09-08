require "rails_helper"

# Issue #238 — la grille jours × services, le goûter facturable et la section
# « À couvrir ».
RSpec.describe "Cuisine — grille jours × services", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "cuisine@les4sources.be", password: "password123") }
  let(:lundi) { Date.current.next_occurring(:monday) + 14 }
  let(:vendredi) { lundi + 4 }
  let(:stay) do
    Stay.create!(customer: Customer.create!(first_name: "Groupe", last_name: "Semaine",
                                            email: "groupe@example.com"),
                 status: "pending", arrival_date: lundi, departure_date: vendredi)
  end

  before { sign_in user }

  def grid_params(cells, overrides = {})
    { grid_mode: "1",
      grid: cells,
      meal_order: { stay_id: stay.id, kind: "repas", people: 8,
                    status: "requested", notes: "Sans gluten" }.merge(overrides) }
  end

  # Le cas réel de Michael : lundi midi → vendredi midi, tous les services.
  # Cinq midis, quatre goûters et quatre soirs — treize services (l'issue en
  # annonce quatorze, mais le vendredi soir le groupe est parti).
  def tous_les_services
    cells = {}
    (lundi..vendredi).each_with_index do |day, index|
      moments = if index.zero? then %w[midi gouter soir]
                elsif day == vendredi then %w[midi]
                else %w[midi gouter soir]
                end
      cells[day.iso8601] = moments.index_with { "1" }
    end
    cells
  end

  describe "GET /kitchen/orders/new" do
    it "rend une grille quand le séjour porte ses deux dates" do
      get new_kitchen_order_path(stay_id: stay.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Services à préparer")
      expect(response.body).to include("meal-grid")
      # Cinq colonnes : arrivée → départ INCLUS.
      (lundi..vendredi).each do |day|
        expect(response.body).to include("grid_#{day.iso8601}_midi")
      end
      expect(response.body).to include("arrivée", "départ")
    end

    it "porte les trois lignes de services, goûter compris" do
      get new_kitchen_order_path(stay_id: stay.id)

      %w[midi gouter soir].each do |moment|
        expect(response.body).to include("grid_#{lundi.iso8601}_#{moment}")
      end
    end

    it "offre les cinq boutons de remplissage" do
      get new_kitchen_order_path(stay_id: stay.id)

      expect(response.body).to include(">Tout<", ">Midis<", ">Soirs<", ">Trio<", ">Rien<")
    end

    it "retombe sur date + moment uniques pour un séjour sans dates" do
      sans_dates = Stay.create!(customer: Customer.create!(first_name: "Sans", last_name: "Dates",
                                                           email: "sd@example.com"),
                                status: "pending")

      get new_kitchen_order_path(stay_id: sans_dates.id)

      expect(response.body).not_to include("Services à préparer")
      expect(response.body).to include("meal_order_moment")
      expect(response.body).to include("meal_order_date")
    end

    it "ne propose plus le type « trio »" do
      get new_kitchen_order_path(stay_id: stay.id)

      expect(response.body).not_to include('value="trio"')
      expect(response.body).to include('value="repas"')
    end
  end

  describe "POST /kitchen/orders en mode grille" do
    it "crée exactement une ligne par case cochée, avec sa date et son moment" do
      expect { post kitchen_orders_path, params: grid_params(tous_les_services) }
        .to change(MealOrder, :count).by(13)

      expect(response).to redirect_to(kitchen_orders_path)
      lignes = stay.meal_orders.chronological
      expect(lignes.where(date: vendredi).pluck(:moment)).to eq(["midi"])
      expect(lignes.where(date: lundi).pluck(:moment)).to match_array(%w[midi gouter soir])
    end

    it "applique le type, les convives et les précisions à toutes les lignes" do
      post kitchen_orders_path, params: grid_params(tous_les_services)

      expect(stay.meal_orders.pluck(:people).uniq).to eq([8])
      expect(stay.meal_orders.pluck(:notes).uniq).to eq(["Sans gluten"])
    end

    it "crée une ligne `gouter` pour la case Goûter et `repas` pour midi et soir" do
      post kitchen_orders_path, params: grid_params(
        { lundi.iso8601 => { "midi" => "1", "gouter" => "1", "soir" => "1" } }
      )

      expect(stay.meal_orders.where(kind: "gouter").count).to eq(1)
      expect(stay.meal_orders.where(kind: "repas").pluck(:moment)).to match_array(%w[midi soir])
    end

    it "totalise le séjour au prix de formule, remise comprise" do
      post kitchen_orders_path, params: grid_params(tous_les_services)

      # 4 journées complètes à 35 €/pers + le midi du vendredi à 15 €/pers, × 8.
      attendu = ((4 * 35_00) + 15_00) * 8
      expect(stay.reload.meal_orders.billable.sum(:price_cents)).to eq(attendu)
    end

    it "n'enregistre rien et affiche une erreur si aucune case n'est cochée" do
      expect { post kitchen_orders_path, params: grid_params({}) }
        .not_to change(MealOrder, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Coche au moins un service")
    end

    it "n'invente pas de goûter pour un buffet" do
      post kitchen_orders_path, params: grid_params(
        { lundi.iso8601 => { "midi" => "1", "gouter" => "1" } }, kind: "buffet_vege"
      )

      expect(stay.meal_orders.pluck(:kind).uniq).to eq(["buffet_vege"])
    end
  end

  describe "la saisie d'un service unique" do
    it "reste possible et n'est pas passée par la grille" do
      expect {
        post kitchen_orders_path, params: {
          meal_order: { stay_id: stay.id, kind: "repas", moment: "midi",
                        date: lundi.iso8601, people: 4, status: "requested" }
        }
      }.to change(MealOrder, :count).by(1)

      expect(MealOrder.last.moment).to eq("midi")
    end
  end

  describe "le formulaire d'édition" do
    it "n'est pas modifié : une ligne, sa date et son moment" do
      order = MealOrder.create!(stay: stay, kind: "repas", moment: "midi", date: lundi,
                                people: 4, status: "requested", skip_notifications: true)

      get edit_kitchen_order_path(order)

      expect(response.body).not_to include("Services à préparer")
      expect(response.body).to include("meal_order_date")
      expect(response.body).to include("meal_order_moment")
    end
  end

  describe "la section « À couvrir »" do
    # Chaque section de la page est un <section> avec son titre en <h2>.
    def section_named(title)
      Nokogiri::HTML(response.body).css("section").find { |node| node.at_css("h2")&.text&.strip == title }
    end

    it "vient en tête, avant « À traiter »" do
      get kitchen_orders_path

      corps = response.body
      expect(corps.index("À couvrir")).to be < corps.index("À traiter")
    end

    it "liste un service refusé encore à venir, avec son motif et son jour" do
      order = MealOrder.create!(stay: stay, kind: "repas", moment: "midi", date: lundi,
                                people: 4, status: "requested", skip_notifications: true)
      order.refuse!("Steph n'est pas là ce mercredi")

      get kitchen_orders_path

      texte = section_named("À couvrir").text
      expect(texte).to include("Steph n'est pas là ce mercredi")
      expect(texte).to include(I18n.l(lundi, format: :long))
    end

    it "le retire d'« Annulés et refusés » tant qu'il est à venir" do
      order = MealOrder.create!(stay: stay, kind: "repas", moment: "midi", date: lundi,
                                people: 4, status: "requested", skip_notifications: true)
      order.refuse!("indisponible")

      get kitchen_orders_path

      expect(section_named("Annulés et refusés").text).not_to include("indisponible")
      expect(section_named("À couvrir").text).to include("indisponible")
    end

    it "n'y liste pas un service que le client a annulé" do
      order = MealOrder.create!(stay: stay, kind: "repas", moment: "midi", date: lundi,
                                people: 4, status: "requested", skip_notifications: true)
      order.refuse!("indisponible")
      order.update!(status: "cancelled", cancellation_reason: "groupe annulé")

      get kitchen_orders_path

      expect(section_named("À couvrir").text).to include("Rien ici")
    end
  end

  describe "la fiche séjour" do
    it "signale les services à couvrir" do
      order = MealOrder.create!(stay: stay, kind: "repas", moment: "midi", date: lundi,
                                people: 4, status: "requested", skip_notifications: true)
      order.refuse!("Steph absente")

      get stay_path(stay)

      expect(response.body).to include("1 service à couvrir")
      expect(response.body).to include("Steph absente")
    end
  end
end
