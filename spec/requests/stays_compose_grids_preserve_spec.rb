require "rails_helper"

# Bug 2026-07-27 (Michael) — changer une date dans le form Séjour rechargeait le
# frame `stay_compose_grids` depuis un Draft ne portant QUE les deux dates :
# tout ce qui vit dans le frame (tentes, vans, hamacs, nuits de gîte, grille
# espaces, note « précision du besoin ») était effacé.
#
# Le form POSTe désormais sa composition COMPLÈTE (mêmes params que #quote) et
# le frame se re-rend sur les nouvelles colonnes SANS perdre la saisie. Les
# valeurs sont conservées PAR INDEX DE NUIT : nuit 1 reste nuit 1, les nuits
# ajoutées arrivent à zéro, les nuits retirées tombent.
RSpec.describe "Stays — rechargement des grilles sans perte de saisie", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-grids-preserve@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:hulotte) { Lodging.create!(name: "La Hulotte", summary: "gîte", price_night_cents: 48_500) }

  let(:arrival) { Date.today + 30 }

  # Cellule stepper « tente » portant une valeur donnée. On matche le TAG entier
  # plutôt qu'un fragment `name="…" value="…"` : Slim réordonne les attributs au
  # rendu (data-*, name, type, value), donc les deux ne sont jamais adjacents et
  # l'ancienne version ne matchait rien — silencieusement, puisque les exemples
  # concernés levaient déjà avant d'arriver ici.
  def tente_field(value)
    /<input[^>]*name="stay\[per_night_resources\]\[tente\]\[\]"[^>]*value="#{value}"[^>]*>/
  end

  def tente_fields_count(body)
    body.scan('name="stay[per_night_resources][tente][]"').size
  end

  def reload(departure:, tente:, extra: {})
    post compose_grids_stays_path,
         params: { stay: {
           customer_mode: "new",
           # `departure` arrive DÉJÀ en ISO des appelants — le reconvertir levait
           # `NoMethodError: undefined method 'iso8601' for String` et les cinq
           # exemples qui passent par ce helper n'ont jamais tourné au vert.
           arrival_date: arrival.iso8601, departure_date: departure.to_s,
           adults: 2, children: 0, dogs_count: 0,
           per_night_resources: { tente: tente }
         }.merge(extra) },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  it "répond en Turbo Stream et remplace le frame des grilles" do
    reload(departure: (arrival + 3).iso8601, tente: %w[2 2 2])

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("stay_compose_grids")
  end

  it "conserve les campeurs déjà saisis quand on RALLONGE le séjour (nuits ajoutées à zéro)" do
    # 3 nuits composées à 2 personnes → départ repoussé à 5 nuits.
    reload(departure: (arrival + 5).iso8601, tente: %w[2 2 2])

    expect(tente_fields_count(response.body)).to eq(5)
    expect(response.body.scan(tente_field(2)).size).to eq(3)
    expect(response.body.scan(tente_field(0)).size).to eq(2)
  end

  it "tronque la grille quand on RACCOURCIT le séjour" do
    reload(departure: (arrival + 2).iso8601, tente: %w[2 2 2 2 2])

    expect(tente_fields_count(response.body)).to eq(2)
    expect(response.body.scan(tente_field(2)).size).to eq(2)
  end

  it "conserve la note « précision du besoin » (espaces), qui vit dans le frame" do
    reload(departure: (arrival + 3).iso8601, tente: %w[1 1 1],
           extra: { spaces_note: "Salle en U, 20 chaises" })

    expect(response.body).to include("Salle en U, 20 chaises")
  end

  # Bug 2026-07-27 : `_compose_grids` rendait un `stay[spaces_note]` EN PLUS de
  # celui que `_spaces_calendar` fournit déjà. Rack retenant la dernière valeur,
  # le champ du bas (vide) écrasait la saisie du champ du haut. Un seul champ,
  # donc — sinon la note se perd en silence à chaque enregistrement.
  it "ne rend QU'UN SEUL champ « précision du besoin »" do
    reload(departure: (arrival + 3).iso8601, tente: %w[0 0 0])

    expect(response.body.scan('name="stay[spaces_note]"').size).to eq(1)
  end

  it "conserve la sélection de gîte nuit par nuit" do
    reload(departure: (arrival + 3).iso8601, tente: %w[0 0 0],
           extra: { lodging_night_ids: [hulotte.id.to_s, hulotte.id.to_s, ""] })

    # Deux cellules sélectionnées (aria-pressed) sur la ligne du gîte.
    expect(response.body.scan(%(aria-pressed="true")).size).to eq(2)
  end

  it "garde le repli GET dates-seules (dégradation sans JS)" do
    get compose_grids_stays_path,
        params: { arrival_date: arrival.iso8601, departure_date: (arrival + 2).iso8601 }

    expect(response).to have_http_status(:ok)
    expect(tente_fields_count(response.body)).to eq(2)
  end
end
