require "rails_helper"

# Choix de la catégorie au formulaire séjour : des TAGS cliquables (Michael
# 2026-07-26) et non plus un <select>. Ce sont de vrais `input[type=radio]`
# masqués — l'exclusivité du choix est garantie par le navigateur.
#
# Le point que ces specs verrouillent : le NOM du champ reste `stay[category]`,
# contrat partagé avec `build_draft` (`params[:stay][:category]`). Changer de
# widget ne doit rien changer au serveur.
RSpec.describe "Formulaire séjour — tags de catégorie", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-chips@les4sources.be", password: "password123") }
  let!(:lodging) { Lodging.create!(name: "Le Grand-Duc", summary: "gîte") }
  let(:arrival) { Date.today + 20 }
  let(:departure) { Date.today + 22 }

  before { sign_in user }

  def create_stay(category: nil)
    draft = Reservations::Draft.new(
      lodging_id: lodging.id, arrival_date: arrival, departure_date: departure,
      adults: 2, first_name: "Alice", last_name: "Martin", email: "alice-chips@example.com"
    )
    builder = Reservations::Builder.new(draft: draft, admin: true, status: "pending", source: "manual")
    builder.run!
    builder.stay.tap { |s| s.update!(category: category) if category }
  end

  def update_params(stay, overrides = {})
    {
      stay: {
        customer_mode: "existing", customer_id: stay.customer_id, new_customer: {},
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        adults: 2, children: 0, dogs_count: 0,
        lodging_id: lodging.id, status: "pending"
      }.merge(overrides)
    }
  end

  describe "rendu des tags" do
    let!(:stay) { create_stay(category: "retreat") }

    it "rend un radio par catégorie, plus une puce « Aucune »" do
      get edit_stay_path(stay)
      expect(response).to have_http_status(:ok)

      radios = response.body.scan(%r{<input[^>]*name="stay\[category\]"[^>]*>})
      expect(radios.size).to eq(Stay::CATEGORIES.size + 1)
      expect(radios).to all(include('type="radio"'))
    end

    it "n'utilise plus un <select> pour la catégorie" do
      get edit_stay_path(stay)
      expect(response.body).not_to match(%r{<select[^>]*name="stay\[category\]"})
    end

    # Slim TRIE les attributs : `checked` sort avant `value`. On isole donc la
    # balise puis on teste ses deux marqueurs, plutôt que de présumer un ordre.
    it "coche la catégorie courante du séjour" do
      get edit_stay_path(stay)
      cochee = response.body.scan(%r{<input[^>]*name="stay\[category\]"[^>]*>}).select { |t| t.include?("checked") }
      expect(cochee.size).to eq(1)
      expect(cochee.first).to include(%(value="retreat"))
    end

    it "coche « Aucune » quand le séjour n'a pas de catégorie" do
      sans_categorie = create_stay
      get edit_stay_path(sans_categorie)
      cochee = response.body.scan(%r{<input[^>]*name="stay\[category\]"[^>]*>}).select { |t| t.include?("checked") }
      expect(cochee.size).to eq(1)
      expect(cochee.first).to include(%(value=""))
    end

    # Les variantes `peer-checked:` doivent apparaître EN TOUTES LETTRES dans le
    # HTML : Tailwind génère son CSS en scannant les sources, une classe
    # assemblée au rendu ne serait jamais produite.
    it "porte les classes d'état cochée en littéral" do
      get edit_stay_path(stay)
      expect(response.body).to include("peer-checked:bg-indigo-600")
      expect(response.body).to include("peer-checked:text-white")
    end
  end

  describe "soumission" do
    it "persiste la catégorie choisie" do
      stay = create_stay
      patch stay_path(stay), params: update_params(stay, category: "couple")
      expect(response).to redirect_to(recent_stays_path)
      expect(stay.reload.category).to eq("couple")
    end

    it "retire la catégorie via la puce « Aucune » (valeur vide)" do
      stay = create_stay(category: "wedding")
      patch stay_path(stay), params: update_params(stay, category: "")
      expect(stay.reload.category).to be_nil
    end

    # Comportement PRÉEXISTANT (inchangé par les tags) : l'update reconstruit un
    # draft complet, donc un `category` absent des params vaut « aucune » et
    # efface. Le formulaire ne peut pas produire ce cas — la puce « Aucune » est
    # cochée par défaut, une valeur part donc toujours. On le documente ici pour
    # qu'un futur appelant hors formulaire ne s'y laisse pas prendre.
    it "efface la catégorie quand le champ n'est pas soumis du tout" do
      stay = create_stay(category: "wedding")
      patch stay_path(stay), params: update_params(stay)
      expect(stay.reload.category).to be_nil
    end
  end
end
