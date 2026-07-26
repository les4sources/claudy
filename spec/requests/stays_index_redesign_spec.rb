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
    # Ancré dans le trimestre COURANT : c'est la page ouverte par défaut depuis
    # le passage à la pagination trimestrielle. `Date.today + 5` pouvait basculer
    # dans le trimestre suivant selon le jour d'exécution.
    debut = Date.today.beginning_of_quarter
    Stay.create!(customer: customer, source: "manual", status: status, notes: notes, category: category,
                 arrival_date: debut + 5, departure_date: debut + 7,
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

    # « Éléments » a été renommée « Composition » et le résumé TEXTE homonyme
    # supprimé (Michael 2026-07-26) : une seule colonne de composition, en icônes.
    it "expose la colonne Catégorie et une SEULE colonne Composition" do
      get stays_path
      expect(response.body).to include("Catégorie")
      expect(response.body).not_to include("Éléments")
      entetes = response.body.scan(%r{<th[^>]*>Composition</th>})
      expect(entetes.size).to eq(1)
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

  # Le trimestre remplace les pastilles « À venir / Passés » (Michael 2026-07-26).
  describe "navigation trimestrielle" do
    let(:trimestre) { Date.today.beginning_of_quarter }
    let!(:ici)      { create_stay(email: "ici@example.com", first: "Dans", last: "Trimestre") }
    let!(:ailleurs) { create_stay(email: "ailleurs@example.com", first: "Autre", last: "Trimestre") }

    before do
      ailleurs.update_columns(arrival_date: trimestre + 4.months,
                              departure_date: trimestre + 4.months + 1.day)
    end

    it "n'affiche que le trimestre courant" do
      get stays_path
      expect(response.body).to include("Dans Trimestre")
      expect(response.body).not_to include("Autre Trimestre")
    end

    it "ne propose plus les pastilles de période" do
      get stays_path
      expect(response.body).not_to include(">À venir<")
      expect(response.body).not_to include(">Passés<")
    end

    # Une recherche doit traverser les trimestres : on ne sait pas d'avance dans
    # lequel tombe ce qu'on cherche.
    it "cherche sur TOUTE la période, hors du trimestre affiché" do
      get stays_path(q: "Autre Trimestre")
      expect(response.body).to include("Autre Trimestre")
      expect(response.body).to include("sur toute la période")
    end

    it "masque la navigation trimestrielle pendant une recherche" do
      get stays_path(q: "Trimestre")
      expect(response.body).not_to include("Navigation par trimestre")
    end
  end

  # Le sélecteur donne un accès DIRECT aux quatre trimestres de l'année, et dit
  # où il y a de la matière — les flèches ← → ne faisaient ni l'un ni l'autre.
  describe "sélecteur de trimestre" do
    let(:annee) { Date.today.year }
    let(:trimestre_courant) { ((Date.today.month - 1) / 3) + 1 }

    it "propose les quatre trimestres de l'année affichée" do
      get stays_path
      (1..4).each { |t| expect(response.body).to include(">T#{t}") }
    end

    it "marque le trimestre courant comme page active" do
      get stays_path
      expect(response.body).to include(%(aria-current="page"))
    end

    it "affiche le nombre de séjours d'un trimestre peuplé" do
      create_stay(email: "compte@example.com")
      get stays_path
      # On cible la pastille ACTIVE par `aria-current` : les flèches d'année
      # portent elles aussi `quarter=<courant>` dans leur href.
      pastille = response.body[%r{<a[^>]*aria-current="page".*?</a>}m]
      expect(pastille).to be_present
      expect(pastille).to include("T#{trimestre_courant}")
      expect(pastille).to include(">1</span>")
    end

    it "éteint et rend non cliquable un trimestre sans séjour" do
      get stays_path
      vide = (1..4).find { |t| t != trimestre_courant }
      expect(response.body).to include(%(aria-disabled="true"))
      expect(response.body).not_to include(%(href="/stays?quarter=#{vide}&amp;year=#{annee}"))
    end

    it "permet de sauter d'une année d'un seul clic" do
      get stays_path
      expect(response.body).to include("Année précédente")
      expect(response.body).to include("Année suivante")
    end
  end

  describe "groupement par mois" do
    let!(:juillet) { create_stay(email: "juil@example.com", first: "Juillet", last: "Client") }
    let!(:aout)    { create_stay(email: "aout@example.com", first: "Aout", last: "Client") }

    # Un trimestre couvre TROIS mois : on place un séjour dans son 1er mois et un
    # autre dans son 2e, tous deux visibles sur la page par défaut.
    let(:trimestre) { Date.today.beginning_of_quarter }
    let(:mois1) { trimestre }
    let(:mois2) { trimestre + 1.month }

    before do
      juillet.update_columns(arrival_date: mois1 + 8, departure_date: mois1 + 10)
      aout.update_columns(arrival_date: mois2 + 2, departure_date: mois2 + 4)
    end

    it "insère une ligne pleine largeur par mois, mois et année en clair" do
      get stays_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.l(mois1, format: "%B %Y").capitalize)
      expect(response.body).to include(I18n.l(mois2, format: "%B %Y").capitalize)
      expect(response.body).to include(%(scope="rowgroup"))
    end

    it "regroupe deux séjours du même mois sous un SEUL en-tête" do
      create_stay(email: "juil2@example.com").update_columns(
        arrival_date: mois1 + 20, departure_date: mois1 + 22
      )
      get stays_path
      expect(response.body.scan(I18n.l(mois1, format: "%B %Y").capitalize).size).to eq(1)
    end

    # Les imports legacy peuvent ne porter aucune date : ils doivent avoir leur
    # propre groupe, jamais être rattachés en silence au mois précédent.
    # Un séjour sans date n'appartient à AUCUN trimestre : le scope le rattrape
    # explicitement, sinon il disparaîtrait de l'index quel que soit le trimestre.
    it "isole les séjours sans date d'arrivée" do
      create_stay(email: "sansdate@example.com").update_columns(arrival_date: nil, departure_date: nil)
      get stays_path
      expect(response.body).to include("Sans date d'arrivée")
    end
  end

  # Depuis une liste de SÉJOURS, cliquer un nom doit montrer le séjour — pas
  # emmener sur la fiche client.
  describe "clic sur le nom du client" do
    let!(:stay) { create_stay(email: "nom@example.com", first: "Ana", last: "Nom") }

    it "ouvre la modale du séjour au lieu de naviguer vers le client" do
      get stays_path
      expect(response.body).not_to include(%(href="#{customer_path(stay.customer)}"))
      # Slim TRIE les attributs : on teste leur PRÉSENCE sur la même balise, pas
      # leur ordre (déjà tombé dans le piège avec `checked` vs `value`).
      bouton = response.body[%r{<button[^>]*data-stay-url="#{Regexp.escape(stay_path(stay))}"[^>]*>}]
      expect(bouton).to be_present
      expect(bouton).to include("stay-details#openFromRow")
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

    it "trouve un séjour d'un AUTRE trimestre que celui affiché" do
      alice.update_columns(arrival_date: Date.today - 200, departure_date: Date.today - 198)
      get stays_path(q: "Durand")
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
      # L'état « non compris » vit dans l'aria-label : le lecteur d'écran ne voit
      # pas la couleur de l'icône, contrairement à l'œil.
      ["Hébergement", "Bivouac", "Van", "Salle", "Cuisine", "Activités"].each do |slot|
        expect(response.body).to include("#{slot} — non compris")
      end
      expect(response.body).to include("text-gray-200")
    end

    # Tooltip CSS (group-hover) et non `title` natif : ce dernier est lent et
    # non stylé, et le navigateur superposerait sa bulle à la nôtre.
    it "porte un tooltip nommant chaque élément" do
      get stays_path
      expect(response.body).to include("group-hover:block")
      ["Hébergement", "Bivouac", "Van", "Salle", "Cuisine", "Activités"].each do |slot|
        expect(response.body).to include(">#{slot}</span>")
      end
    end

    it "allume l'hébergement quand le séjour en comporte un" do
      booking = Booking.create!(firstname: "T", from_date: Date.today + 5, to_date: Date.today + 7, adults: 2)
      StayItem.create!(stay: stay, bookable: booking)

      get stays_path
      expect(response.body).to include(%(aria-label="Hébergement"))
      expect(response.body).not_to include("Hébergement — non compris")
    end
  end
end
