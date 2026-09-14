require "rails_helper"

# Epic #234, Phase 3 — l'UX de la section « Espaces » : un geste pour une ligne
# entière, un résumé en clair sous la grille, des bornes de séjour repérables et
# des indications de tarif qui viennent de Paramètres > Tarifs.
#
# Les mêmes attentes sont vérifiées côté funnel public dans
# `spec/requests/public/reservation_spaces_grid_ux_spec.rb` : c'est le MÊME
# partial, la parité fait partie du contrat (décision 7 de l'epic).
RSpec.describe "Séjours — UX de la grille Espaces (epic #234, Phase 3)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-ux-espaces@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:lodging) do
    l = Lodging.create!(name: "La Hulotte", summary: "gîte")
    l.rooms << Room.create!(name: "Chambre 1", code: "CH1", level: 1)
    l
  end
  let!(:petite_salle) { Space.create!(name: "Petite Salle", code: "SAU", capacity: 1) }

  let(:lundi)    { (Date.today + 30).next_occurring(:monday) }
  let(:vendredi) { lundi + 4 }

  def grille(body)
    Nokogiri::HTML(body)
  end

  describe "« Tous les jours » et « Effacer »" do
    it "pose les deux boutons sur chaque ligne d'espace" do
      get compose_grids_stays_path, params: { arrival_date: lundi.iso8601, departure_date: vendredi.iso8601 }

      doc = grille(response.body)
      remplir = doc.css(%(button[data-action*="public--spaces-calendar#fillRow"]))
      vider   = doc.css(%(button[data-action*="public--spaces-calendar#clearRow"]))

      expect(remplir.size).to eq(3) # grande salle, petite salle, cuisine pro
      expect(vider.size).to eq(3)
      expect(remplir.map(&:text).map(&:strip).uniq).to eq(["Tous les jours"])
      expect(vider.map(&:text).map(&:strip).uniq).to eq(["Effacer"])
      # Chaque bouton dit SUR QUELLE LIGNE il agit — c'est ce que lit le
      # contrôleur Stimulus, et ce qui rend le libellé accessible non ambigu.
      expect(remplir.map { |b| b["data-public--spaces-calendar-key-param"] })
        .to match_array(%w[grande_salle petite_salle cuisine_pro])
      expect(remplir.map { |b| b["aria-label"] }).to include("Petite Salle — poser la journée sur tous les jours")
    end
  end

  describe "résumé en clair" do
    it "rend une ligne de résumé par espace, masquée tant que rien n'est choisi" do
      get compose_grids_stays_path, params: { arrival_date: lundi.iso8601, departure_date: vendredi.iso8601 }

      lignes = grille(response.body).css("[data-summary-for]")
      expect(lignes.map { |l| l["data-summary-for"] }).to match_array(%w[grande_salle petite_salle cuisine_pro])
      expect(lignes.map { |l| l["class"].to_s }).to all(include("hidden"))
    end

    it "dit en français ce qui est déjà réservé, sans montant" do
      post stays_path, params: {
        stay: {
          customer_mode: "new",
          new_customer: { first_name: "Groupe", last_name: "Semaine", email: "ux-espaces@example.com" },
          arrival_date: lundi.iso8601, departure_date: vendredi.iso8601,
          adults: 2, children: 0, dogs_count: 0,
          lodging_id: lodging.id, status: "confirmed",
          space_slots: { petite_salle: %w[journee journee journee journee journee_et_soiree] }
        }
      }
      stay = Stay.order(:created_at).last

      get edit_stay_path(stay)

      ligne = grille(response.body).at_css(%([data-summary-for="petite_salle"]))
      expect(ligne["class"].to_s).not_to include("hidden")
      texte = ligne.text.gsub(/\s+/, " ").strip
      # 5 journées (dont une doublée d'une soirée) + 1 soirée, du lundi au vendredi.
      expect(texte).to eq("Petite Salle · 5 journées · + 1 soirée · lun #{lundi.strftime('%-d')} → ven #{vendredi.strftime('%-d')}")
      expect(texte).not_to match(/€/)
    end
  end

  describe "indications de tarif" do
    it "les dérive du catalogue et mentionne le forfait 5 jours" do
      get compose_grids_stays_path, params: { arrival_date: lundi.iso8601, departure_date: vendredi.iso8601 }

      expect(response.body).to include("140 €/j · 90 €/soir · 525 € les 5 jours")
    end

    it "suit Paramètres > Tarifs sans redéploiement" do
      Rate.create!(key: "hall.petite_salle.journee", amount_cents: 15_500, label: "Petite salle — journée")
      Pricing::Rates.reset!

      get compose_grids_stays_path, params: { arrival_date: lundi.iso8601, departure_date: vendredi.iso8601 }

      expect(response.body).to include("155 €/j")
      expect(response.body).not_to include("140 €/j")
    ensure
      Pricing::Rates.reset!
    end
  end

  describe "bornes du séjour et défilement" do
    it "teinte les colonnes d'arrivée et de départ" do
      get compose_grids_stays_path, params: { arrival_date: lundi.iso8601, departure_date: vendredi.iso8601 }

      entetes = grille(response.body).css("thead th")
      bornes  = entetes.select { |th| th["class"].to_s.include?("spaces-grid-edge") }

      expect(bornes.size).to eq(2)
      expect(bornes.first.text).to include("arrivée")
      expect(bornes.last.text).to include("départ")
    end

    it "n'affiche pas les flèches jusqu'à 7 jours, les affiche au-delà" do
      get compose_grids_stays_path, params: { arrival_date: lundi.iso8601, departure_date: (lundi + 6).iso8601 }
      expect(response.body).not_to include("public--spaces-calendar#nextNights")

      get compose_grids_stays_path, params: { arrival_date: lundi.iso8601, departure_date: (lundi + 7).iso8601 }
      expect(response.body).to include("public--spaces-calendar#nextNights")
    end
  end
end
