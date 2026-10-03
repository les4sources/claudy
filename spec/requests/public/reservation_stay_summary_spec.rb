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
  # Le 5 d'un mois à venir : arrivée et départ tombent dans le même mois, comme
  # le suppose le récap attendu (« 5 → 9 nov. »). Avec `Date.today + 60`, la
  # spec échouait les jours où le séjour chevauchait deux mois.
  let(:arrival)   { (Date.today + 60).beginning_of_month + 4 }
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

  # Refait le 2026-10-03 : le détail reprend les lignes du DEVIS (le tiroir
  # « Voir le devis »), mot pour mot, plutôt qu'un résumé maison.
  it "reprend les lignes du devis, avec le total et l'acompte" do
    html = Nokogiri::HTML(response.body)
    drawer = html.css("#reservation_quote li > span:first-child").map { |s| s.text.squish }
    recap = html.css(".funnel-recap__lines li > span:first-child").map { |s| s.text.squish }

    expect(drawer).to include(a_string_starting_with("La Hulotte — nuit du"))
    expect(recap).to eq(drawer)
    expect(response.body).to include("Total TVAC")
    expect(response.body).to include("Acompte 50 % à la confirmation")
  end

  it "annonce la composition du groupe" do
    expect(response.body).to include("10 adultes · 2 enfants")
  end

  describe "ligne du temps" do
    let(:html) { Nokogiri::HTML(response.body) }
    let(:rows) { html.css(".stay-timeline__row:not(.stay-timeline__row--head)") }

    def row(label) = rows.find { |r| r.at_css(".stay-timeline__label").text.strip == label }
    def bars(label) = row(label).css(".stay-timeline__bar")

    # 5 jours, départ inclus : la grille des espaces est indexée par JOUR.
    it "montre chaque jour, de l'arrivée au départ" do
      expect(html.css(".stay-timeline__day").size).to eq(5)
      expect(html.at_css(".stay-timeline")["style"]).to include("--tl-days: 5")
    end

    # Le gîte part le soir de l'arrivée (colonne 2) et s'arrête le matin du
    # départ (colonne 10) : 4 nuits identiques ne font qu'une barre.
    it "pose l'hébergement en une barre, du soir d'arrivée au matin du départ" do
      expect(bars("Hébergement").map { |b| [b.text.strip, b["style"]] })
        .to eq([["La Hulotte", "grid-column: 2 / 10"]])
    end

    it "pose chaque salle sur ses journées ou ses soirées" do
      expect(bars("Petite Salle").size).to eq(5)
      expect(bars("Petite Salle").first["title"]).to eq("Journée")
      expect(bars("Grande Salle").map { |b| [b["title"], b["style"]] })
        .to eq([["Soirée", "grid-column: 4 / 5"], ["Soirée", "grid-column: 6 / 7"]])
      expect(row("Cuisine pro")).to be_nil
    end

    it "compte le camping nuit par nuit" do
      expect(bars("Camping").map { |b| [b.text.strip, b["style"]] })
        .to eq([["4 pers.", "grid-column: 2 / 8"]])
      expect(row("Van")).to be_nil
    end
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
