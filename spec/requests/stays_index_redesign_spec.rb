require "rails_helper"

# Refonte du tableau /stays (Michael 2026-07-26) : plus d'ID, catégorie éditable
# en ligne, recherche multi-champs, teinte de ligne par statut, colonne Montant
# unique (solde dû en dessous / check vert si soldé) et rangée d'icônes de
# composition à emplacements fixes.
RSpec.describe "Index Séjours — refonte du tableau", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-refonte@les4sources.be", password: "password123") }
  before { sign_in user }

  def create_stay(email:, status: "pending", total_cents: 0, first: "Jean", last: "Test", notes: nil, category: nil)
    customer = Customer.create!(email: email, first_name: first, last_name: last)
    Stay.create!(customer: customer, source: "manual", status: status, notes: notes, category: category,
                 arrival_date: Date.today + 5, departure_date: Date.today + 7,
                 total_amount_cents: total_cents)
  end

  describe "colonnes" do
    let!(:stay) { create_stay(email: "colonnes@example.com", total_cents: 10_000) }

    it "retire l'ID, « Encaissé » et « Reste dû », et renomme « Total » en « Montant »" do
      get stays_path
      expect(response).to have_http_status(:ok)

      expect(response.body).not_to include("Encaissé")
      expect(response.body).not_to include("Reste dû")
      expect(response.body).to include("Montant")
      # « Paiement » retirée à son tour : redondante avec la colonne Montant.
      expect(response.body).not_to include(">Paiement<")
      # Le lien « #<id> » de l'ancienne première colonne a disparu.
      expect(response.body).not_to include(">##{stay.id}<")
    end

    it "expose les nouvelles colonnes Catégorie et Éléments" do
      get stays_path
      expect(response.body).to include("Catégorie")
      expect(response.body).to include("Éléments")
    end
  end

  describe "dropdown de catégorie en ligne" do
    let!(:stay) { create_stay(email: "cat@example.com", category: "family") }

    it "rend un select prérempli ciblant update_category avec from=index" do
      get stays_path
      expect(response.body).to include(%(id="stay-category-#{stay.id}"))
      expect(response.body).to include(update_category_stay_path(stay))
      expect(response.body).to include(%(value="index"))
      # Le nom du champ est le CONTRAT avec `update_category` (params[:stay][:category]).
      # Un `category=…` nu ferait lire nil au contrôleur, qui EFFACERAIT la catégorie.
      expect(response.body).to include(%(name="stay[category]"))
      # Catégorie courante sélectionnée + libellé FR d'une autre catégorie dispo.
      expect(response.body).to include(%(<option selected="selected" value="family">Famille</option>))
      expect(response.body).to include("Couple")
    end

    it "met à jour la catégorie et répond en Turbo Stream sur la seule cellule" do
      patch update_category_stay_path(stay),
            params: { from: "index", stay: { category: "wedding" } },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(target="stay-category-#{stay.id}"))
      expect(stay.reload.category).to eq("wedding")
    end

    it "permet de retirer la catégorie (valeur vide)" do
      patch update_category_stay_path(stay),
            params: { from: "index", stay: { category: "" } },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(stay.reload.category).to be_nil
    end

    it "refuse une catégorie hors liste sans casser la cellule" do
      patch update_category_stay_path(stay),
            params: { from: "index", stay: { category: "pas_une_categorie" } },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Catégorie invalide")
      expect(stay.reload.category).to eq("family")
    end

    # La modale séjour utilise la MÊME route sans `from` : son comportement
    # historique (redirection vers la fiche) ne doit pas avoir bougé.
    it "conserve la redirection vers la fiche quand l'appel ne vient pas de l'index" do
      patch update_category_stay_path(stay), params: { stay: { category: "retreat" } }
      expect(response).to redirect_to(stay_path(stay))
    end
  end

  # Le canal d'attribution est du bruit (présent sur chaque ligne) ; la
  # PLATEFORME, elle, change la façon de traiter la réservation.
  describe "badges du client" do
    let!(:direct) { create_stay(email: "direct@example.com", first: "Direct", last: "Client") }
    let!(:ota)    { create_stay(email: "ota@example.com", first: "Ota", last: "Client") }

    before do
      booking = Booking.create!(firstname: "T", from_date: Date.today + 5, to_date: Date.today + 7,
                                adults: 2, platform: "airbnb")
      StayItem.create!(stay: ota, bookable: booking)
    end

    it "n'affiche plus le canal d'attribution" do
      get stays_path
      expect(response.body).not_to include("Saisie manuelle")
      expect(response.body).not_to include("Réservation en ligne")
    end

    # ICÔNE et non libellé (Michael 2026-07-26) : le SVG partagé, pas le mot.
    it "affiche l'ICÔNE de la plateforme pour une réservation OTA" do
      get stays_path
      expect(response.body).to include(%(aria-label="Airbnb"))
      # Le partial SVG partagé est bien rendu, teinté à la couleur de marque.
      expect(response.body).to include("fill-current text-rose-500")
      expect(response.body).to match(%r{<span[^>]*aria-label="Airbnb"[^>]*>\s*<svg}m)
    end

    it "ne rend plus l'ancien badge texte de plateforme" do
      get stays_path
      expect(response.body).not_to include("bg-rose-50 text-rose-600")
    end
  end

  # « Tous » retiré : on est toujours sur une période, « À venir » par défaut.
  describe "filtres de période" do
    let!(:futur) { create_stay(email: "futur@example.com", first: "Futur", last: "Client") }
    let!(:passe) { create_stay(email: "passe@example.com", first: "Passe", last: "Client") }

    before { passe.update_columns(arrival_date: Date.today - 20, departure_date: Date.today - 18) }

    it "affiche « À venir » par défaut, sans séjour passé" do
      get stays_path
      expect(response.body).to include("Futur Client")
      expect(response.body).not_to include("Passe Client")
    end

    it "ne propose plus le filtre « Tous »" do
      get stays_path
      expect(response.body).not_to include(">Tous<")
    end

    it "bascule sur « Passés »" do
      get stays_path(filter: "past")
      expect(response.body).to include("Passe Client")
      expect(response.body).not_to include("Futur Client")
    end

    it "retombe sur « À venir » pour une valeur de filtre inconnue" do
      get stays_path(filter: "n_importe_quoi")
      expect(response.body).to include("Futur Client")
      expect(response.body).not_to include("Passe Client")
    end

    # Garde-fou : sans le OR sur `departure_date IS NULL`, un séjour sans date
    # ne serait dans AUCUNE des deux vues et disparaîtrait de l'index.
    it "rattrape les séjours sans date dans « À venir »" do
      sans_date = create_stay(email: "sansdate2@example.com", first: "Sans", last: "Date")
      sans_date.update_columns(arrival_date: nil, departure_date: nil)
      get stays_path
      expect(response.body).to include("Sans Date")
    end
  end

  describe "groupement par mois" do
    let!(:juillet) { create_stay(email: "juil@example.com", first: "Juillet", last: "Client") }
    let!(:aout)    { create_stay(email: "aout@example.com", first: "Aout", last: "Client") }

    before do
      juillet.update_columns(arrival_date: Date.new(2027, 7, 9),  departure_date: Date.new(2027, 7, 11))
      aout.update_columns(arrival_date: Date.new(2027, 8, 3), departure_date: Date.new(2027, 8, 5))
    end

    it "insère une ligne pleine largeur par mois, mois et année en clair" do
      get stays_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Juillet 2027")
      expect(response.body).to include("Août 2027")
      expect(response.body).to include(%(scope="rowgroup"))
    end

    it "regroupe deux séjours du même mois sous un SEUL en-tête" do
      create_stay(email: "juil2@example.com").update_columns(
        arrival_date: Date.new(2027, 7, 20), departure_date: Date.new(2027, 7, 22)
      )
      get stays_path
      expect(response.body.scan("Juillet 2027").size).to eq(1)
    end

    # Les imports legacy peuvent ne porter aucune date : ils doivent avoir leur
    # propre groupe, jamais être rattachés en silence au mois précédent.
    it "isole les séjours sans date d'arrivée" do
      create_stay(email: "sansdate@example.com").update_columns(arrival_date: nil, departure_date: nil)
      get stays_path
      expect(response.body).to include("Sans date d'arrivée")
    end
  end

  describe "recherche" do
    let!(:alice) { create_stay(email: "alice@example.com", first: "Alice", last: "Durand") }
    let!(:bruno) { create_stay(email: "bruno@example.com", first: "Bruno", last: "Martin", notes: "Vient avec un chien") }

    it "rend le champ de recherche ciblant le frame de résultats" do
      get stays_path
      expect(response.body).to include(%(name="q"))
      expect(response.body).to include("stays-results")
    end

    it "filtre sur le nom du client" do
      get stays_path(q: "Durand")
      expect(response.body).to include("Alice Durand")
      expect(response.body).not_to include("Bruno Martin")
    end

    it "filtre sur un mot de la note interne" do
      get stays_path(q: "chien")
      expect(response.body).to include("Bruno Martin")
      expect(response.body).not_to include("Alice Durand")
    end

    it "affiche le compte de résultats et un lien d'effacement" do
      get stays_path(q: "Durand")
      expect(response.body).to include("1 résultat")
      expect(response.body).to include("Effacer")
    end

    it "annonce l'absence de résultat sans casser la page" do
      get stays_path(q: "zorglub-introuvable")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Aucun séjour ne correspond à cette recherche")
    end

    it "se combine avec le filtre de période" do
      alice.update_columns(arrival_date: Date.today - 20, departure_date: Date.today - 18)
      get stays_path(filter: "past", q: "Durand")
      expect(response.body).to include("Alice Durand")
      expect(response.body).not_to include("Bruno Martin")
    end
  end

  describe "teinte de ligne par statut" do
    let!(:confirmed) { create_stay(email: "conf@example.com", status: "confirmed") }
    let!(:canceled)  { create_stay(email: "canc@example.com", status: "canceled") }

    it "applique une teinte verte au confirmé et rouge à l'annulé" do
      get stays_path
      expect(response.body).to include("bg-green-50")
      expect(response.body).to include("bg-red-50")
    end
  end

  describe "colonne Montant" do
    let!(:stay) { create_stay(email: "solde@example.com", total_cents: 20_000) }

    it "affiche le solde dû en petit sous le montant quand il reste à payer" do
      get stays_path
      expect(response.body).to include("Solde dû")
    end

    it "affiche un check vert et aucun solde dû quand tout est encaissé" do
      Payment.create!(stay: stay, amount_cents: 20_000, status: "paid", payment_method: "transfer")
      get stays_path
      expect(response.body).to include("Intégralement payé")
      expect(response.body).not_to include("Solde dû")
    end
  end

  describe "rangée d'icônes de composition" do
    let!(:stay) { create_stay(email: "compo@example.com") }

    it "rend les 6 emplacements, éteints par défaut" do
      get stays_path
      expect(response.body).to include("Hébergement — non compris")
      expect(response.body).to include("Salle — non compris")
      expect(response.body).to include("Cuisine — non compris")
      expect(response.body).to include("Activité — non compris")
      # Le camping-car a son emplacement propre depuis 2026-07-26.
      expect(response.body).to include("Camping-car — non compris")
      expect(response.body).to include("text-gray-200")
    end

    it "allume l'hébergement quand le séjour en comporte un" do
      booking = Booking.create!(firstname: "T", from_date: Date.today + 5, to_date: Date.today + 7, adults: 2)
      StayItem.create!(stay: stay, bookable: booking)

      get stays_path
      expect(response.body).to include(%(title="Hébergement"))
      expect(response.body).not_to include("Hébergement — non compris")
    end
  end
end
