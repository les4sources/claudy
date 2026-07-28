require "rails_helper"

# Demande Michael 2026-07-27 : « teste bien que tout changement dans le
# formulaire doit provoquer des changements cohérents dans la composition
# possible ».
#
# Le form n'a que deux canaux vivants — `stays#quote` (remplace le panneau de
# devis) et `stays#compose_grids` (remplace le frame de composition). Cette spec
# fixe le contrat des DEUX, champ par champ : ce qu'on change à gauche, et ce que
# ça doit produire à droite. Un test de navigateur ne vaut que le jour où on le
# lance ; ces exemples-ci tournent à chaque commit.
RSpec.describe "Stays — cohérence composition ↔ devis dans le form", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-coherence@les4sources.be", password: "password123") }
  before { sign_in user }

  # `bookable_lodgings` ne retient que les gîtes tarifés au catalogue : un gîte
  # inventé de toutes pièces n'apparaîtrait pas dans la grille.
  let(:nom_gite) { Pricing::Catalog::LODGING_RATES.keys.first }
  let!(:gite) { Lodging.find_or_create_by!(name: nom_gite) { |l| l.price_night_cents = 48_500 } }

  let(:arrivee) { Date.today + 40 }
  let(:depart)  { arrivee + 2 }

  def base_params(extra = {})
    { customer_mode: "new", arrival_date: arrivee.iso8601,
      departure_date: depart.iso8601, adults: 2, children: 0, dogs_count: 0 }.merge(extra)
  end

  def devis(extra = {})
    post quote_stays_path, params: { stay: base_params(extra) },
                           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    response.body
  end

  def grilles(extra = {})
    post compose_grids_stays_path, params: { stay: base_params(extra) },
                                   headers: { "Accept" => "text/vnd.turbo-stream.html" }
    response.body
  end

  # Total affiché EN TÊTE de la carte de devis (le `text-2xl`), en centimes. On
  # vise ce span précis plutôt que « le premier montant du corps » : le money gem
  # rend « 485 € » sans décimales et « 22,50 € » avec, et les séparateurs de
  # milliers sont des espaces insécables — d'où le nettoyage brutal.
  def total_cents(corps)
    gros = corps[/text-2xl[^>]*>([^<]+)</, 1]
    return 0 if gros.nil?

    chiffres = gros.gsub(/[^\d,]/, "")
    return 0 if chiffres.empty?

    (chiffres.tr(",", ".").to_f * 100).round
  end

  describe "les dates pilotent la fenêtre de composition" do
    it "rend une colonne par nuit dans les grilles" do
      corps = grilles
      expect(corps.scan('name="stay[per_night_resources][tente][]"').size).to eq(2)
    end

    it "suit un allongement du séjour" do
      post compose_grids_stays_path,
           params: { stay: base_params(departure_date: (arrivee + 5).iso8601) },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.body.scan('name="stay[per_night_resources][tente][]"').size).to eq(5)
    end
  end

  describe "l'hébergement alimente le devis" do
    it "sans gîte choisi, rien de facturable" do
      expect(total_cents(devis)).to eq(0)
    end

    it "choisir un gîte pour chaque nuit fait apparaître une ligne chiffrée" do
      corps = devis(lodging_night_ids: [gite.id.to_s, gite.id.to_s])

      expect(total_cents(corps)).to be > 0
      expect(corps).to include(nom_gite)
    end

    it "une nuit de plus coûte plus cher" do
      deux = total_cents(devis(lodging_night_ids: [gite.id.to_s, gite.id.to_s]))

      post quote_stays_path,
           params: { stay: base_params(departure_date: (arrivee + 3).iso8601,
                                       lodging_night_ids: [gite.id.to_s] * 3) },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(total_cents(response.body)).to be > deux
    end
  end

  describe "le camping alimente le devis" do
    it "des campeurs sous tente produisent une ligne chiffrée" do
      corps = devis(per_night_resources: { tente: %w[3 3] })

      expect(total_cents(corps)).to be > 0
    end

    it "plus de campeurs, plus cher" do
      trois = total_cents(devis(per_night_resources: { tente: %w[3 3] }))
      six   = total_cents(devis(per_night_resources: { tente: %w[6 6] }))

      expect(six).to be > trois
    end
  end

  describe "le mode chambres seules coupe le devis automatique" do
    it "annonce que le total passe par le prix imposé" do
      corps = devis(booking_type: "rooms", lodging_id: gite.id.to_s,
                    room_ids: gite.rooms.limit(1).pluck(:id).map(&:to_s))

      expect(corps).to include("Pas de calcul automatique")
    end
  end

  describe "les états vides du rail de prix" do
    # Le devis vivait en bas de page ; il est désormais la carte qu'on regarde en
    # composant. Une carte vide se lirait comme un bug — elle doit se raconter.
    it "dit explicitement qu'il n'y a rien à facturer plutôt que d'afficher un blanc" do
      expect(devis).to include("Rien de facturable")
    end
  end
end
