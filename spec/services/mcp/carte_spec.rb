require "rails_helper"

# Les outils de la carte du domaine et des plantes (Michael, 2026-10-06) :
# plantes, espèces, récoltes, tâches, notes, fils, relevés, objets — aperçu
# d'abord, accord ensuite.
RSpec.describe Mcp::Server, "carte et plantes" do
  let!(:chloe) { Human.create!(name: "Chloé", email: "chloe@example.com") }
  let(:user) { User.create!(email: "chloe@example.com", password: "secret123456", human: chloe) }
  let(:server) { described_class.new(user: user) }
  let(:bob) { User.create!(email: "bob@example.com", password: "secret123456") }

  def outil(name, arguments, serveur: server)
    serveur.handle({ "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call",
                     "params" => { "name" => name, "arguments" => arguments } })[:result]
  end

  def texte(result) = result[:content].first[:text]

  def confirme(name, arguments, serveur: server)
    apercu = outil(name, arguments, serveur: serveur)
    expect(apercu[:isError]).to be(false), texte(apercu)
    resultat = outil(name, arguments.merge("confirmation" => texte(apercu)[/confirmation: "([^"]+)"/, 1]), serveur: serveur)
    expect(resultat[:isError]).to be(false), texte(resultat)
    resultat
  end

  def refus(name, arguments, serveur: server)
    resultat = outil(name, arguments, serveur: serveur)
    expect(resultat[:isError]).to be(true), texte(resultat)
    texte(resultat)
  end

  it "crée une plante avec une espèce nouvelle, la place, puis la soigne" do
    apercu = texte(outil("enregistrer_plante", { "espece" => "Néflier", "variete" => "Nottingham", "numero" => "42",
                                                 "zone" => "Verger", "strate" => "Arbuste", "nom_latin" => "Mespilus germanica" }))
    expect(apercu).to include("Nouvelle plante", "Néflier Nottingham", "n°42")
    expect(PlantSpecies.count).to eq(0)

    confirme("enregistrer_plante", { "espece" => "Néflier", "variete" => "Nottingham", "numero" => "42",
                                     "zone" => "Verger", "strate" => "Arbuste", "nom_latin" => "Mespilus germanica" })
    plante = Plant.last
    expect(plante).to have_attributes(stratum: "shrub", zone: "Verger", status: "planted", created_by: user)
    expect(plante.plant_species).to have_attributes(name: "Néflier", latin_name: "Mespilus germanica")
    expect(PaperTrail::Version.where(item: plante).last.whodunnit).to start_with("claude:chloe@example.com")

    confirme("enregistrer_plante", { "plante" => "n°42", "latitude" => 50.3349, "longitude" => 4.8571, "sante" => "Inquiétante" })
    plante.reload
    expect(plante).to be_placed
    expect(plante.health).to eq("worrying")
    expect(plante.map_feature.geometry["coordinates"]).to eq([4.8571, 50.3349])

    expect(texte(outil("plantes", { "recherche" => "neflier" }))).to include("##{plante.id} n°42", "placée (50.334900")
    expect(texte(outil("fiche_plante", { "plante" => plante.id }))).to include("Mespilus germanica", "Inquiétante")

    refus("enregistrer_plante", { "plante" => plante.id, "supprimer" => true })
    confirme("enregistrer_plante", { "plante" => plante.id, "supprimer" => true, "motif" => "arbre mort de la grêle" })
    expect(Plant.find_by(id: plante.id)).to be_nil
    expect(MapFeature.find_by(id: plante.map_feature_id)).to be_nil
  end

  it "refuse une variété sans espèce et un numéro déjà pris" do
    Plant.create!(name: "Pommier 1", number: 7)
    expect(refus("enregistrer_plante", { "nom" => "Sans espèce", "variete" => "Reinette" })).to include("indique d'abord l'espèce")
    expect(refus("enregistrer_plante", { "nom" => "Doublon", "numero" => "7" })).to include("déjà pris")
  end

  it "tient le calendrier de récolte : hérité de l'espèce, puis propre, puis rendu à l'espèce" do
    pommier = PlantSpecies.create!(name: "Pommier")
    plante = Plant.create!(name: "Pommier du haut", plant_species: pommier)

    confirme("calendrier_recolte", { "espece" => "Pommier", "recoltes" => { "fruit" => %w[sept oct] } })
    expect(texte(outil("fiche_plante", { "plante" => plante.id }))).to include("Récolte (héritée de l'espèce) : Fruit : sept., oct.")

    confirme("calendrier_recolte", { "plante" => plante.id, "recoltes" => { "Fruit" => [10], "fleur" => ["avril"] } })
    expect(plante.harvest_windows.reload.map { |f| [f.part, f.months] }).to contain_exactly(["fruit", [10]], ["flower", [4]])
    expect(texte(outil("calendrier_recoltes", { "mois" => [4] }))).to include("Avril", "Pommier du haut — Fleur")

    confirme("calendrier_recolte", { "plante" => plante.id, "effacer" => true })
    expect(plante.harvest_windows.reload).to be_empty
    expect(refus("calendrier_recolte", { "plante" => plante.id, "recoltes" => { "fruit" => [] } })).to include("au moins un mois")
  end

  it "gère le catalogue : fiche, variétés, et refuse ce qui porte encore des plantes" do
    confirme("enregistrer_espece", { "nom" => "Poirier", "nom_latin" => "Pyrus communis", "exposition" => %w[Soleil],
                                     "varietes_ajouter" => ["Conférence", "Doyenné"] })
    poirier = PlantSpecies.find_by!(name: "Poirier")
    expect(poirier.varieties.map(&:name)).to eq(%w[Conférence Doyenné])

    confirme("enregistrer_espece", { "espece" => "Poirier", "varietes_renommer" => { "Doyenné" => "Doyenné du Comice" } })
    Plant.create!(name: "Poirier 1", plant_species: poirier, plant_variety: poirier.varieties.find_by!(name: "Conférence"))

    expect(refus("enregistrer_espece", { "espece" => "Poirier", "varietes_supprimer" => ["Conférence"] })).to include("1 plante(s) vivante(s)")
    expect(refus("enregistrer_espece", { "espece" => "Poirier", "supprimer" => true, "motif" => "doublon" })).to include("en dépendent")
    expect(texte(outil("especes", { "espece" => "poirier" }))).to include("Pyrus communis", "Doyenné du Comice", "Conférence #")
  end

  it "ajoute tâches et notes à une plante et à un objet, puis le carnet les range par mois" do
    plante = Plant.create!(name: "Groseillier")
    prairie = MapLayer.for_kind(:management).map_features.create!(
      feature_kind: "zone", name_i18n: { "fr" => "Prairie du bas" },
      geometry: { "type" => "Polygon", "coordinates" => [[[4.85, 50.33], [4.86, 50.33], [4.86, 50.34], [4.85, 50.33]]] }
    )

    confirme("tache_carte", { "geste" => "ajouter", "plante" => plante.id, "libelle" => "Taille", "mois" => ["février"] })
    confirme("tache_carte", { "geste" => "ajouter", "element" => prairie.id, "libelle" => "Fauche des orties", "mois" => [6, 9] })
    expect(MapTask.last).to have_attributes(sector: "terrain", months: [6, 9])
    carnet = texte(outil("carnet_taches", { "mois" => [6] }))
    expect(carnet).to include("Fauche des orties", "Prairie du bas")
    expect(carnet).not_to include("Taille")

    tache = MapTask.last
    confirme("tache_carte", { "geste" => "modifier", "tache" => tache.id, "mois" => [7] })
    expect(tache.reload.months).to eq([7])
    confirme("tache_carte", { "geste" => "supprimer", "tache" => tache.id, "motif" => "fauche abandonnée" })
    expect(MapTask.find_by(id: tache.id)).to be_nil

    confirme("note_carte", { "geste" => "ajouter", "plante" => "Groseillier", "texte" => "Bourgeons gelés", "date" => "2026-03-12" })
    note = plante.map_notes.first
    expect(note).to have_attributes(body: "Bourgeons gelés", noted_on: Date.new(2026, 3, 12), author: user)
    expect(texte(outil("fiche_plante", { "plante" => plante.id }))).to include("Bourgeons gelés", "Taille")
    confirme("note_carte", { "geste" => "supprimer", "note" => note.id, "motif" => "erreur de plante" })
    expect(plante.map_notes.reload).to be_empty
  end

  it "ouvre un fil, notifie à la réponse, résout, et ne supprime que ses propres messages" do
    confirme("fil_carte", { "geste" => "ouvrir", "latitude" => 50.334, "longitude" => 4.857, "texte" => "La clôture est cassée ici" })
    racine = MapComment.roots.last
    expect(racine.map_feature.geometry["coordinates"]).to eq([4.857, 50.334])

    serveur_bob = described_class.new(user: bob)
    apercu = texte(outil("fil_carte", { "geste" => "repondre", "message" => racine.id, "texte" => "Je passe demain" }, serveur: serveur_bob))
    expect(apercu).to include("Notifié(s) : Chloé")
    expect do
      confirme("fil_carte", { "geste" => "repondre", "message" => racine.id, "texte" => "Je passe demain" }, serveur: serveur_bob)
    end.to change { Notification.where(recipient: user).count }.by(1)

    expect(refus("fil_carte", { "geste" => "supprimer", "message" => racine.id, "motif" => "x" }, serveur: serveur_bob)).to include("propres messages")
    confirme("fil_carte", { "geste" => "resoudre", "message" => racine.id }, serveur: serveur_bob)
    expect(racine.reload).to be_resolved
    expect(texte(outil("fils_carte", { "statut" => "resolus" }))).to include("Fil ##{racine.id} résolu", "Je passe demain")

    confirme("fil_carte", { "geste" => "supprimer", "message" => racine.id, "motif" => "réparée" })
    expect(MapFeature.find_by(id: racine.map_feature_id)).to be_nil
  end

  it "crée, corrige et supprime un relevé de biodiversité" do
    confirme("releve_biodiversite", { "geste" => "creer", "latitude" => 50.335, "longitude" => 4.858, "regne" => "Faune",
                                      "espece" => "Chevêche d'Athéna", "effectif" => 2, "date" => "2026-10-01" })
    releve = MapFeature.observations.last
    expect(releve).to have_attributes(species_common: "Chevêche d'Athéna", realm: "fauna", observation_count: 2, observer_id: user.id)

    expect(refus("releve_biodiversite", { "geste" => "modifier", "releve" => releve.id, "date" => (Date.current + 3).iso8601 })).to include("futur")
    confirme("releve_biodiversite", { "geste" => "modifier", "releve" => releve.id, "nom_latin" => "Athene noctua", "description" => "Sur le vieux pommier" })
    expect(releve.reload.species_latin).to eq("Athene noctua")
    expect(texte(outil("biodiversite", { "regne" => "fauna" }))).to include("Chevêche d'Athéna (Athene noctua) ×2", "1 espèce(s)")

    confirme("releve_biodiversite", { "geste" => "supprimer", "releve" => releve.id, "motif" => "doublon" })
    expect(MapFeature.observations.count).to eq(0)
  end

  it "pose un robinet sur le réseau d'eau, modifie sa fiche et refuse ce qui relève d'un autre outil" do
    confirme("element_carte", { "geste" => "creer_point", "couche" => "eau", "latitude" => 50.333, "longitude" => 4.856,
                                "nom" => "Robinet du potager", "type_noeud" => "tap", "origine_eau" => "Eau de pluie" })
    robinet = MapFeature.last
    expect(robinet).to have_attributes(feature_kind: "node", node_type: "tap", water_source: "rain")
    expect(robinet.map_layer.network).to eq("water")

    confirme("element_carte", { "geste" => "modifier", "element" => robinet.id, "consigne" => "Quart de tour à droite",
                                "latitude" => 50.3331, "longitude" => 4.8561 })
    expect(robinet.reload.instructions).to eq("Quart de tour à droite")
    expect(robinet.geometry["coordinates"]).to eq([4.8561, 50.3331])
    expect(texte(outil("elements_carte", { "couche" => "eau", "recherche" => "potager" }))).to include("Objet ##{robinet.id} Robinet du potager")

    expect(refus("element_carte", { "geste" => "creer_point", "couche" => "accueil", "latitude" => 50.3, "longitude" => 4.8 })).to include("nom en français")
    plante = Plant.create!(name: "Cassissier")
    plante.place!(latitude: 50.33, longitude: 4.85)
    expect(refus("element_carte", { "geste" => "modifier", "element" => plante.map_feature_id, "nom" => "X" })).to include("enregistrer_plante")

    confirme("element_carte", { "geste" => "supprimer", "element" => robinet.id, "motif" => "robinet démonté" })
    expect(MapFeature.find_by(id: robinet.id)).to be_nil
  end

  it "reste fermé à un porteur d'activité" do
    porteur = User.create!(email: "porteur@example.com", password: "secret123456", restricted_to_experiences: true)
    expect(outil("plantes", {}, serveur: described_class.new(user: porteur))[:isError]).to be(true)
  end
end
