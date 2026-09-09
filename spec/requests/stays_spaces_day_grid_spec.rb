require "rails_helper"

# Epic #234, Phase 1 — la grille « Espaces » couvre chaque JOUR du séjour, du
# jour d'arrivée au jour de DÉPART INCLUS.
#
# Cas réel (Michael, 2026-09-06) : un groupe vient du lundi au vendredi, dort 4
# nuits dans la Hulotte et réserve la Petite Salle les 5 jours. Le formulaire
# n'avait pas de colonne le vendredi, et une réservation d'espace datée du jour
# du départ était JETÉE au premier enregistrement du formulaire d'édition.
#
# Les grilles à la NUIT (hébergement, camping, van, hamac) gardent [arrivée,
# départ) — on ne dort pas la nuit du départ.
RSpec.describe "Séjours — grille Espaces par jour (epic #234, Phase 1)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-jours@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:lodging) do
    l = Lodging.create!(name: "La Hulotte", summary: "gîte")
    l.rooms << Room.create!(name: "Chambre 1", code: "CH1", level: 1)
    l
  end
  let!(:petite_salle) { Space.create!(name: "Petite Salle", code: "SAU", capacity: 1) }

  # Ancré sur un LUNDI : le barème des salles distingue semaine et week-end, et
  # le cas de l'issue est précisément « lundi → vendredi ».
  let(:lundi)    { (Date.today + 30).next_occurring(:monday) }
  let(:vendredi) { lundi + 4 }

  def base_params(overrides = {})
    {
      stay: {
        customer_mode: "new",
        new_customer: { first_name: "Groupe", last_name: "Semaine", email: "groupe@example.com" },
        arrival_date: lundi.iso8601, departure_date: vendredi.iso8601,
        adults: 2, children: 0, dogs_count: 0,
        lodging_id: lodging.id, status: "confirmed"
      }.merge(overrides)
    }
  end

  # 5 colonnes : lundi, mardi, mercredi, jeudi, vendredi.
  def cinq_journees
    { petite_salle: %w[journee journee journee journee journee] }
  end

  # La grille ESPACES seule — la page porte aussi des grilles à la NUIT
  # (hébergement, camping, van), qui gardent légitimement leurs en-têtes « Nuit N ».
  def grille_espaces(body)
    Nokogiri::HTML(body)
      .css("table")
      .find { |t| t.at_css(%(input[name="stay[space_slots][petite_salle][]"])) }
  end

  describe "GET /stays/compose_grids — les colonnes sont des JOURS" do
    it "rend 5 colonnes pour un séjour de 4 nuits, la dernière datée du vendredi" do
      get compose_grids_stays_path, params: { arrival_date: lundi.iso8601, departure_date: vendredi.iso8601 }

      expect(response).to have_http_status(:ok)
      entetes = grille_espaces(response.body).css("thead th").map { |th| th.text.strip }

      expect(entetes.grep(/Jour \d/).size).to eq(5)
      expect(entetes.join).to include("Jour 1").and include("Jour 5")
      expect(entetes.join).not_to include("Jour 6")
      # Plus jamais « Nuit N » dans la grille ESPACES (les grilles à la nuit,
      # elles, gardent le mot — c'est leur vocabulaire).
      expect(entetes.join).not_to include("Nuit")
      # La dernière colonne porte bien la date du vendredi.
      expect(entetes.last).to include("Ven #{vendredi.strftime('%-d/%-m')}")
    end

    it "distingue la colonne d'arrivée et celle de départ" do
      get compose_grids_stays_path, params: { arrival_date: lundi.iso8601, departure_date: vendredi.iso8601 }

      expect(response.body).to include("arrivée")
      expect(response.body).to include("départ")
    end

    # Une journée sèche (0 nuit) n'avait AUCUNE colonne : la grille par nuit
    # renvoyait [] et le form retombait sur les lignes `halls` sans date.
    it "rend UNE colonne pour un séjour à la journée (arrivée = départ)" do
      get compose_grids_stays_path, params: { arrival_date: lundi.iso8601, departure_date: lundi.iso8601 }

      expect(response.body).to include("Jour 1")
      expect(response.body).not_to include("Jour 2")
      expect(response.body).to include("arrivée et départ")
      expect(response.body).to include(%(name="stay[space_slots][petite_salle][]"))
    end

    it "porte un aria-label daté sur chaque cellule, jamais « nuit »" do
      get compose_grids_stays_path, params: { arrival_date: lundi.iso8601, departure_date: vendredi.iso8601 }

      expect(response.body).to include("Petite Salle — jour 5,")
      expect(response.body).not_to include("Petite Salle — nuit")
    end

    # Les grilles à la NUIT ne bougent pas : 4 nuits pour lundi → vendredi.
    it "laisse la grille hébergement sur les NUITS, départ exclu" do
      get compose_grids_stays_path, params: { arrival_date: lundi.iso8601, departure_date: vendredi.iso8601 }

      grille_gite = Nokogiri::HTML(response.body)
                            .css("table")
                            .find { |t| t.at_css(%(button[data-type="lodging"])) }
      entetes = grille_gite.css("thead th").map { |th| th.text.strip }

      expect(entetes.grep(/Nuit \d/).size).to eq(4)
      expect(entetes.join).not_to include("Nuit 5")
    end
  end

  describe "POST /stays — la salle se réserve jusqu'au jour du départ" do
    it "crée 5 SpaceReservation, dont une le vendredi" do
      post stays_path, params: base_params(space_slots: cinq_journees)

      stay = Stay.order(:created_at).last
      sb = stay.stay_items.where(bookable_type: "SpaceBooking").first.bookable
      expect(sb.space_reservations.count).to eq(5)
      expect(sb.space_reservations.map(&:date).sort).to eq((lundi..vendredi).to_a)
      expect(sb.space_reservations.find_by(date: vendredi).duration).to eq("day")
    end

    it "rend la salle indisponible le jour du départ" do
      post stays_path, params: base_params(space_slots: cinq_journees)

      expect(petite_salle.reload.available_on?(vendredi)).to be(false)
      expect(petite_salle.available_on?(vendredi + 1)).to be(true)
    end

    # `Stay#recompute_aggregates!` dérive la fenêtre du séjour des réservables :
    # un espace le jour du départ ne doit pas la décaler.
    it "ne décale pas la fenêtre du séjour" do
      post stays_path, params: base_params(space_slots: cinq_journees)

      stay = Stay.order(:created_at).last
      expect(stay.arrival_date).to eq(lundi)
      expect(stay.departure_date).to eq(vendredi)
    end

    it "réserve la salle sur un séjour à la journée (0 nuit)" do
      post stays_path, params: base_params(
        lodging_id: "", departure_date: lundi.iso8601,
        space_slots: { petite_salle: %w[journee] }
      )

      stay = Stay.order(:created_at).last
      sb = stay.stay_items.where(bookable_type: "SpaceBooking").first.bookable
      expect(sb.space_reservations.map(&:date)).to eq([lundi])
    end
  end

  describe "édition — la réservation du jour du départ SURVIT" do
    it "conserve les 5 réservations après un aller-retour edit → patch" do
      post stays_path, params: base_params(space_slots: cinq_journees)
      stay = Stay.order(:created_at).last
      expect(stay.stay_items.where(bookable_type: "SpaceBooking").first.bookable.space_reservations.count).to eq(5)

      # Le formulaire d'édition reconstruit la grille depuis les SpaceReservation…
      get edit_stay_path(stay)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Jour 5")

      # …et un enregistrement SANS modification ne doit rien perdre.
      patch stay_path(stay), params: {
        stay: {
          customer_mode: "existing", customer_id: stay.customer_id, new_customer: {},
          arrival_date: lundi.iso8601, departure_date: vendredi.iso8601,
          adults: 2, children: 0, dogs_count: 0,
          lodging_id: lodging.id, status: "confirmed",
          space_slots: cinq_journees
        }
      }

      stay.reload
      sb = stay.stay_items.where(bookable_type: "SpaceBooking").first.bookable
      expect(sb.space_reservations.count).to eq(5)
      expect(sb.space_reservations.map(&:date)).to include(vendredi)
    end

    # Cas de l'import : la ligne existe en base, le formulaire la voit désormais.
    it "préremplit la grille avec une réservation datée du jour du départ" do
      post stays_path, params: base_params(space_slots: { petite_salle: ["", "", "", "", "journee"] })
      stay = Stay.order(:created_at).last

      get edit_stay_path(stay)

      doc = Nokogiri::HTML(response.body)
      valeurs = doc.css(%(input[name="stay[space_slots][petite_salle][]"])).map { |i| i["value"] }
      expect(valeurs).to eq(["", "", "", "", "journee"])
    end
  end

  describe "devis" do
    it "facture les 5 journées au forfait 5 jours, jour du départ compris" do
      # Phase 2 : la journée du vendredi est de la grille SEMAINE, et une suite
      # de cinq journées vaut le forfait « 5 jours » du site — 525 €, contre
      # 5 × 140 € = 700 € à l'unité.
      post stays_path, params: base_params(lodging_id: "", space_slots: cinq_journees)

      stay = Stay.order(:created_at).last
      expect(stay.total_amount_cents)
        .to eq(Pricing::Catalog.hall_package_cents("petite_salle", "cinq_jours"))
      expect(stay.total_amount_cents).to eq(52_500)
    end

    it "étiquette chaque ligne du devis par sa DATE, plus par un numéro de nuit" do
      post quote_stays_path,
           params: base_params(lodging_id: "", space_slots: { petite_salle: ["", "", "", "", "journee"] }),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Petite Salle")
      expect(response.body).not_to include("nuit 5")
    end
  end

  # Le calendrier ne change pas : `Calendar::DayStayBlocks` regroupe déjà les
  # SpaceReservation par date. Ce qui lui manquait, c'était la réservation du
  # vendredi — que la grille sait enfin produire. Spec de non-régression.
  describe "calendrier" do
    it "affiche le bloc du séjour le vendredi, avec la salle et SANS 💤" do
      post stays_path, params: base_params(space_slots: cinq_journees)
      stay = Stay.order(:created_at).last

      get "/", params: { date: lundi.iso8601 }

      expect(response).to have_http_status(:ok)
      # 5 jours rendus pour ce séjour : 4 nuits d'hébergement + le jour du départ.
      expect(response.body.scan(%(data-stay-id="#{stay.id}")).size).to eq(5)

      # Les blocs sont imbriqués : on les lit en DOM, pas à la regex.
      blocs = Nokogiri::HTML(response.body)
                      .css(%(div[data-stay-id="#{stay.id}"]))
                      .map(&:to_html)
      expect(blocs.size).to eq(5)

      # Le dernier bloc du séjour est celui du VENDREDI : la salle occupe, on ne
      # dort pas — donc badge de salle, et pas de 💤.
      expect(blocs.last).to include("SAU")
      expect(blocs.last).not_to include("💤")
      # Le jeudi (avant-dernier), on dort encore — et la salle est là aussi.
      expect(blocs[-2]).to include("💤")
      expect(blocs[-2]).to include("SAU")
    end
  end
end
