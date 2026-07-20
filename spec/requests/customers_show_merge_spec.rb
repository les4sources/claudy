require "rails_helper"

# Fusion de séjours DEPUIS la fiche client + addendums (numéro de TVA, rendu des
# notes internes). La fiche réutilise le contrôleur Stimulus `stay-merge` du
# calendrier : on vérifie ici le CÂBLAGE serveur (data-attributes des lignes,
# bouton flottant conditionnel, values du contrôleur) — le comportement JS est
# couvert par le calendrier.
RSpec.describe "Customer show — fusion de séjours + coordonnées/notes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { User.create!(email: "staff-cust@les4sources.be", password: "password123") }
  before { sign_in admin }

  def add_stay(customer, offset)
    Stay.create!(customer: customer, status: "confirmed",
                 arrival_date: Date.today + offset, departure_date: Date.today + offset + 2)
  end

  describe "mode fusion sur la fiche client" do
    let(:customer) { Customer.create!(email: "multi@example.com", customer_type: "individual", first_name: "Multi") }

    context "avec au moins 2 séjours" do
      before do
        add_stay(customer, 3)
        add_stay(customer, 10)
        get customer_path(customer)
      end

      it "câble le contrôleur stay-merge avec les values de la fiche (return-url scopée)" do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("stay-details stay-merge")
        expect(response.body).to include("data-stay-merge-setup-url-value")
        expect(response.body).to include("data-stay-merge-preview-url-value")
        expect(response.body).to include(%(data-stay-merge-return-url-value="#{customer_path(customer)}"))
        expect(response.body).to include(%(data-stay-merge-scope-value="customer-#{customer.id}"))
      end

      it "porte data-stay-id sur chaque ligne de séjour (cible de sélection)" do
        doc = Nokogiri::HTML(response.body)
        rows = doc.css("li[data-stay-id]")
        expect(rows.size).to eq(2)
        expect(rows.map { |r| r["data-stay-id"] }).to match_array(customer.stays.pluck(:id).map(&:to_s))
        # Label + dates présents (ce que le contrôleur lit pour les chips).
        expect(rows.all? { |r| r.key?("data-stay-label") }).to be(true)
      end

      it "affiche le bouton flottant « Fusionner les séjours »" do
        doc = Nokogiri::HTML(response.body)
        fab = doc.at_css("button.merge-fab")
        expect(fab).to be_present
        expect(fab.text).to include("Fusionner les séjours")
      end
    end

    context "avec moins de 2 séjours" do
      it "n'affiche PAS le bouton flottant (rien à fusionner)" do
        add_stay(customer, 3)
        get customer_path(customer)
        expect(response).to have_http_status(:ok)
        # Le sélecteur CSS `.merge-fab` existe dans la feuille de style partagée ;
        # on vérifie donc l'absence du BOUTON, pas de la sous-chaîne.
        expect(Nokogiri::HTML(response.body).at_css("button.merge-fab")).to be_nil
      end
    end
  end

  describe "numéro de TVA (addendum)" do
    it "affiche le numéro de TVA d'une organisation quand il est renseigné" do
      org = Customer.create!(email: "org@example.com", customer_type: "organization",
                             organization_name: "Les 4 Sources ASBL", vat_number: "BE0123456789")
      get customer_path(org)
      expect(response.body).to include("Numéro de TVA")
      expect(response.body).to include("BE0123456789")
    end

    it "n'affiche pas le bloc TVA pour un particulier" do
      indiv = Customer.create!(email: "indiv@example.com", customer_type: "individual", first_name: "Jean")
      get customer_path(indiv)
      expect(response.body).not_to include("Numéro de TVA")
    end
  end

  describe "notes internes (addendum — rendu ActionText)" do
    it "rend le contenu riche NON échappé quand la note existe" do
      customer = Customer.create!(email: "noted@example.com", customer_type: "individual", first_name: "Noté")
      customer.update!(notes: "<strong>Client VIP</strong>")
      get customer_path(customer)
      expect(response.body).to include("Notes internes")
      expect(response.body).to include("<strong>Client VIP</strong>")
      expect(response.body).not_to include("&lt;strong&gt;")
    end

    it "masque entièrement le bloc quand la note est vide" do
      customer = Customer.create!(email: "empty@example.com", customer_type: "individual", first_name: "Vide")
      get customer_path(customer)
      expect(response.body).not_to include("Notes internes")
      expect(response.body).not_to include("trix-content")
    end
  end
end
