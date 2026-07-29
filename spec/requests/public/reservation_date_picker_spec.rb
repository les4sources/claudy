require "rails_helper"

# Le calendrier de disponibilités EST le sélecteur de dates (2026-07-29).
#
# Avant, il s'ouvrait en lecture seule : le client consultait, refermait, puis
# retapait ses dates dans deux champs `jj/mm/aaaa`. Il choisit désormais sa
# plage directement dessus, et « Choisir ces dates » remplit les deux champs.
#
# Le comportement lui-même vit dans le Stimulus `public--avail-cal` ; ces specs
# gardent le CONTRAT de balisage dont il dépend — retirer une de ces accroches
# casserait le sélecteur en silence, sans qu'aucun test ne bronche.
RSpec.describe "Public::Reservations — sélecteur de dates du calendrier", type: :request do
  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre 1", level: 1)
    l
  end

  describe "étape 1" do
    before { get "/reservation/sejour" }

    it "rend un dialogue accessible" do
      expect(response.body).to include('role="dialog"')
      expect(response.body).to include('aria-modal="true"')
      expect(response.body).to include('aria-labelledby="avail_modal_title"')
      expect(response.body).to include('id="avail_modal_title"')
    end

    it "porte le contrôleur de sélection SUR LE PANNEAU, hors du turbo-frame" do
      # Le frame `avail_cal` est remplacé à chaque changement de mois. Si le
      # contrôleur vivait dedans, la plage en cours de sélection serait perdue
      # en passant de septembre à octobre.
      panneau = response.body[/<div[^>]*role="dialog".*?>/m]
      expect(panneau).to include('data-controller="public--avail-cal"')
    end

    it "expose les accroches du pied de modale" do
      expect(response.body).to include('data-public--avail-cal-target="summary"')
      expect(response.body).to include('data-public--avail-cal-target="confirm"')
      expect(response.body).to include('data-public--avail-cal-target="hint"')
      expect(response.body).to include("Choisir ces dates")
    end

    it "annonce le mois affiché, pour pouvoir sauter à celui du séjour" do
      expect(response.body).to include("data-cal-month=")
    end

    it "rend des cellules datées cliquables" do
      # Slim échappe le `>` de la syntaxe Stimulus en `&gt;` dans l'attribut.
      expect(response.body).to include("data-action=\"click-&gt;public--avail-cal#selectDay\"")
      expect(response.body).to match(/data-date="\d{4}-\d{2}-\d{2}"/)
    end
  end

  describe "navigation de mois" do
    it "sert le mois demandé avec sa propre étiquette" do
      mois = (Date.today >> 3).strftime("%Y-%m")
      get "/reservation/calendrier", params: { month: mois }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(data-cal-month="#{mois}"))
    end

    it "borne la navigation au mois courant — pas de passé" do
      passe = (Date.today << 6).strftime("%Y-%m")
      get "/reservation/calendrier", params: { month: passe }

      expect(response.body).to include(%(data-cal-month="#{Date.today.strftime('%Y-%m')}"))
    end
  end
end
