require "rails_helper"

# Le funnel /reservation est passé de quatre à TROIS étapes le 2026-09-08
# (décision Michael) : dates → composition → coordonnées.
#
# L'étape « Activités » demandait au visiteur de choisir un créneau daté au
# moment de la demande, alors que l'équipe ne construit le calendrier des
# activités qu'un mois avant le séjour. Ces exemples verrouillent les deux
# choses qui cassent en silence quand on retire une étape : le repère d'étapes
# (qui continuerait d'annoncer « sur 4 ») et la cible du POST de composition
# (qui renverrait vers une route disparue).
RSpec.describe "Public::Reservations — funnel à trois étapes", type: :request do
  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre 1", level: 1)
    l
  end

  let(:arrival)   { (Date.today + 60).iso8601 }
  let(:departure) { (Date.today + 63).iso8601 }

  def pose_les_dates
    post "/reservation/sejour",
         params: { reservation: { arrival_date: arrival, departure_date: departure, adults: 2 } }
  end

  before { pose_les_dates }

  it "n'annonce que trois étapes sur le repère de la composition" do
    get "/reservation/composer"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Étape 2 sur 3")
    expect(response.body).to include("Composition")
    expect(response.body).to include("Coordonnées")
    # Plus aucun lien vers l'étape disparue, à aucune largeur d'écran.
    expect(response.body).not_to include("/reservation/activites")
  end

  it "n'annonce que trois étapes sur le repère des coordonnées" do
    get "/reservation/coordonnees"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Étape 3 sur 3")
    expect(response.body).not_to include("/reservation/activites")
  end

  it "envoie la composition directement vers les coordonnées" do
    post "/reservation/composer",
         params: { reservation: { lodging_night_ids: [hulotte.id.to_s, "", ""] } }

    expect(response).to redirect_to("/reservation/coordonnees")
  end

  it "propose de continuer vers les coordonnées, plus vers les activités" do
    post "/reservation/devis",
         params: { reservation: { arrival_date: arrival, departure_date: departure,
                                  lodging_night_ids: [hulotte.id.to_s, "", ""] } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.body).to include("Continuer vers mes coordonnées")
    expect(response.body).not_to include("Continuer vers les activités")
  end

  # Le bloc « Activités » de l'étape 2 survit, mais il ne promet plus qu'une
  # chose : l'équipe revient vers vous. Il disait auparavant « les activités se
  # réservent » ET « vous recevrez un email » — le visiteur ne savait pas s'il
  # devait agir tout de suite.
  it "explique que l'équipe planifie les activités un mois avant le séjour" do
    get "/reservation/composer"

    expect(response.body).to include("Activités aux 4 Sources")
    expect(response.body).to include("Notre équipe planifie les activités un mois avant votre séjour.")
  end
end
