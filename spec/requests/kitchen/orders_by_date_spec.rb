require "rails_helper"

# Epic #321, phase 1 — la page Cuisine se lit par date.
#
# Réunion Pôle Accueil × Cuisine du 2026-09-11. La table était groupée par
# séjour : pour savoir ce qu'on cuisine demain, il fallait la parcourir entière.
# Le groupement disparaît, le client devient une colonne, et l'ordre de lecture
# devient celui du travail.
RSpec.describe "Cuisine — la page se lit par date", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-kitchen-date@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:godinne) do
    Customer.create!(email: "godinne-date@example.com", customer_type: "organization",
                     organization_name: "École de Godinne")
  end
  let(:scouts) do
    Customer.create!(email: "scouts-date@example.com", customer_type: "organization",
                     organization_name: "Scouts d'Yvoir")
  end

  def stay_for(customer, arrival:)
    Stay.create!(customer: customer, source: "manual", status: "pending",
                 arrival_date: arrival, departure_date: arrival + 2)
  end

  def line(stay, **attrs)
    stay.meal_orders.create!({ kind: "repas", people: 10 }.merge(attrs))
  end

  def ids_on(view = :all)
    get kitchen_orders_path(view: view)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body).css("tr[id^=order-]").map { |tr| tr["id"].delete_prefix("order-").to_i }
  end

  describe "l'ordre de lecture" do
    it "trie par date de service croissante, tous séjours confondus" do
      tot = stay_for(godinne, arrival: Date.current + 5)
      tard = stay_for(scouts, arrival: Date.current + 20)

      # Saisies dans le désordre ET sur deux séjours : c'est exactement le cas
      # que le groupement rendait illisible.
      lointain = line(tard, date: Date.current + 21)
      proche   = line(tot, date: Date.current + 6)
      milieu   = line(tard, date: Date.current + 20)

      expect(ids_on).to eq([proche.id, milieu.id, lointain.id])
    end

    # Une demande dont la date n'est pas fixée est la PLUS urgente à traiter,
    # pas la moins : c'est celle dont on ne sait encore rien.
    it "met les demandes sans date en tête" do
      stay = stay_for(godinne, arrival: Date.current + 5)
      datee = line(stay, date: Date.current + 6)
      sans_date = line(stay, date: nil)

      expect(ids_on).to eq([sans_date.id, datee.id])
    end

    it "garde le tri antichronologique sur les archives" do
      stay = stay_for(godinne, arrival: Date.current - 30)
      vieux = line(stay, date: Date.current - 30, validation: "accepted")
      recent = line(stay, date: Date.current - 3, validation: "accepted")

      expect(ids_on(:past)).to eq([recent.id, vieux.id])
    end
  end

  describe "la table" do
    let!(:stay) { stay_for(godinne, arrival: Date.current + 5) }
    let!(:commande) { line(stay, date: Date.current + 6) }

    it "n'a plus d'en-tête de séjour : une ligne par service" do
      get kitchen_orders_path(view: :all)

      lignes = Nokogiri::HTML(response.body).css("tbody tr")
      expect(lignes.size).to eq(1)
      expect(lignes.first["id"]).to eq("order-#{commande.id}")
    end

    it "porte les colonnes « Demandée le » et « Client », dans l'ordre décrit" do
      get kitchen_orders_path(view: :all)

      entetes = Nokogiri::HTML(response.body).css("thead th").map { |th| th.text.strip }
      expect(entetes.first(4)).to eq(["Demandée le", "Date", "Client", "Type"])
    end

    it "affiche le client dans sa colonne, en lien vers le séjour" do
      get kitchen_orders_path(view: :all)

      cellules = Nokogiri::HTML(response.body).css("#order-#{commande.id} td")
      client = cellules[2]
      expect(client.text).to include("École de Godinne")
      expect(client.at_css("a")["href"]).to eq(stay_path(stay))
    end

    it "affiche la date de saisie au format court" do
      get kitchen_orders_path(view: :all)

      cellules = Nokogiri::HTML(response.body).css("#order-#{commande.id} td")
      expect(cellules[0].text).to include(I18n.l(commande.created_at.to_date, format: "%-d/%m/%y"))
    end

    # Le « ah zut, elle date d'il y a un petit temps » de Malau : un signal, pas
    # une alerte.
    it "signale en ambre une demande que la cuisine n'a pas tranchée depuis 14 jours" do
      commande.update_column(:created_at, 20.days.ago)

      get kitchen_orders_path(view: :all)

      expect(Nokogiri::HTML(response.body).css("#order-#{commande.id} td").first.to_html).to include("text-amber-700")
    end

    it "ne signale pas une demande déjà tranchée, même ancienne" do
      commande.update!(validation: "accepted")
      commande.update_column(:created_at, 20.days.ago)

      get kitchen_orders_path(view: :all)

      expect(Nokogiri::HTML(response.body).css("#order-#{commande.id} td").first.to_html).not_to include("text-amber-700")
    end
  end

  # Rien de ce qui existait ne doit disparaître en route (Definition of Done de
  # l'epic) : la demande orpheline garde sa pastille et son rattachement.
  describe "une demande sans séjour" do
    let!(:orpheline) do
      MealOrder.create!(kind: "repas", people: 12, date: Date.current + 8,
                        contact_label: "Comité des fêtes", status: "requested",
                        skip_notifications: true)
    end

    it "garde son nom libre, sa pastille et son menu de rattachement" do
      get kitchen_orders_path(view: :all)

      ligne = Nokogiri::HTML(response.body).at_css("#order-#{orpheline.id}")
      expect(ligne.css("td")[2].text).to include("Comité des fêtes")
      expect(ligne.css("td")[2].text).to include("sans séjour")
      expect(CGI.unescapeHTML(ligne.to_html)).to include("Rattacher à un séjour")
    end
  end

  # Le sous-total par séjour disparaît avec les groupes ; le total facturable en
  # pied de table, lui, ne bouge pas.
  describe "le total facturable" do
    it "reste affiché dans la vue du Pôle Accueil" do
      stay = stay_for(godinne, arrival: Date.current + 5)
      line(stay, date: Date.current + 6, status: "requested", validation: "accepted",
                 unit_price_cents: 1_500)

      get kitchen_orders_path(view: :reception)

      expect(response.body).to include("Total facturable")
    end
  end
end
