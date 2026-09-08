require "rails_helper"

# Récap de l'étape coordonnées — la DERNIÈRE chose que le client relit avant
# d'envoyer sa demande. Il ne montrait que le gîte et les dates : une salle
# réservée cinq jours, quatre campeurs et douze personnes disparaissaient du
# résumé, et l'erreur de saisie partait avec la demande.
RSpec.describe "Public::Reservations — récap de l'étape coordonnées", type: :request do
  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre 1", level: 1)
    l
  end

  # 4 nuits → 5 JOURS de grille espaces (départ inclus).
  let(:arrival)   { Date.today + 60 }
  let(:departure) { arrival + 4 }

  # Le mois abrégé vient d'I18n, comme dans la vue : la spec ne doit pas
  # dépendre de la date du jour où on la lance.
  def jour(date) = "#{date.day} #{I18n.t("date.abbr_month_names")[date.month]}"

  before do
    post "/reservation/sejour",
         params: { reservation: { arrival_date: arrival.iso8601, departure_date: departure.iso8601,
                                  adults: 10, children: 2 } }

    post "/reservation/devis",
         params: { reservation: {
           arrival_date: arrival.iso8601, departure_date: departure.iso8601,
           adults: 10, children: 2,
           group_name: "Les Compagnons du Levain",
           lodging_night_ids: Array.new(4) { hulotte.id.to_s },
           space_slots: { petite_salle: Array.new(5) { "journee" },
                          grande_salle: ["", "soiree", "soiree", "", ""],
                          cuisine_pro: Array.new(5) { "" } },
           per_night_resources: { tente: %w[4 4 4 0], van: %w[0 0 0 0],
                                  hamac_simple: %w[0 0 0 0], hamac_double: %w[0 0 0 0] }
         } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    get "/reservation/coordonnees"
  end

  it "rend la page" do
    expect(response).to have_http_status(:ok)
  end

  it "regroupe l'hébergement par gîte, en nuits" do
    expect(response.body).to include("La Hulotte — 4 nuits")
  end

  it "annonce la composition du groupe" do
    expect(response.body).to include("10 adultes · 2 enfants")
  end

  # La grille des espaces est indexée par JOUR, départ inclus : 5 jours pour
  # 4 nuits. Une lecture sur l'axe des nuits amputerait le dernier jour.
  it "résume les espaces par salle, période et fenêtre de dates" do
    expect(response.body).to include("Petite salle — 5 journées (#{arrival.day} → #{jour(departure)})")
    expect(response.body).to include("Grande salle — 2 soirées")
  end

  # Le récap ne lisait que la PREMIÈRE entrée de camping : « 4 personnes », sans
  # jamais dire combien de nuits.
  it "compte le camping en personnes-nuits" do
    expect(response.body).to include("Camping tente")
    expect(response.body).to include("4 pers. × 3 nuits")
  end

  it "reprend le nom du groupe" do
    expect(response.body).to include("Les Compagnons du Levain")
  end

  # Le choix de l'animal se pose à l'étape 1, avec les dates et le groupe : le
  # lien « Modifier » de ce bloc renvoyait vers la composition, où il n'y a rien
  # à modifier pour un chien.
  it "renvoie le « Modifier » de l'animal vers l'étape 1" do
    bloc_animal = response.body[/Animal de compagnie.*?<\/div>\s*<\/div>/m]

    expect(bloc_animal).to be_present
    expect(bloc_animal).to include(%(href="/reservation/sejour">Modifier</a>))
    expect(bloc_animal).not_to include(%(href="/reservation/composer">Modifier</a>))
  end

  it "garde le « Modifier » du récap vers la composition" do
    expect(response.body).to include(%(href="/reservation/composer">Modifier</a>))
  end
end
