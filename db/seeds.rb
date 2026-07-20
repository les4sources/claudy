# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)

lodging_8 = Lodging.find_or_create_by!(name: "La Chevêche") { |l| l.summary = "4 à 8 personnes"; l.price_night = 240; l.available_for_bookings = true; l.show_on_reports = true }
lodging_16 = Lodging.find_or_create_by!(name: "La Hulotte") { |l| l.summary = "9 à 16 personnes"; l.price_night = 480; l.available_for_bookings = true; l.show_on_reports = true }
lodging_25 = Lodging.find_or_create_by!(name: "Le Grand-Duc") { |l| l.summary = "17 à 25 personnes"; l.price_night = 750; l.party_hall_availability = true; l.available_for_bookings = true; l.show_on_reports = true }
lodging_tents = Lodging.find_or_create_by!(name: "Espace tentes") { |l| l.summary = "Dans la pâture"; l.price_night = 0; l.available_for_bookings = false; l.show_on_reports = false }
lodging_vans = Lodging.find_or_create_by!(name: "Espace camping-cars") { |l| l.summary = "Sur le parking"; l.price_night = 0; l.available_for_bookings = false; l.show_on_reports = false }
lodging_tiny = Lodging.find_or_create_by!(name: "Tiny house") { |l| l.summary = "2 personnes"; l.price_night = 0; l.available_for_bookings = false; l.show_on_reports = true }

room_romarin = Room.find_or_create_by!(code: "ROM") { |r| r.name = "Romarin"; r.level = 0; r.description = "2 lits simples adaptables en lit double + lit superposé" }
room_balsamine = Room.find_or_create_by!(code: "BAL") { |r| r.name = "Balsamine"; r.level = 0; r.description = "2 lits simples adaptables en lit double + lit superposé" }
room_lavande = Room.find_or_create_by!(code: "LAV") { |r| r.name = "Lavande"; r.level = 1; r.description = "2 lits simples adaptables en lit double" }
room_melisse = Room.find_or_create_by!(code: "MEL") { |r| r.name = "Mélisse"; r.level = 1; r.description = "3 lits simples" }
room_capucine = Room.find_or_create_by!(code: "CAP") { |r| r.name = "Capucine"; r.level = 1; r.description = "3 lits simples" }
room_sarriette = Room.find_or_create_by!(code: "SAR") { |r| r.name = "Sarriette"; r.level = 2; r.description = "2 lits simples adaptables en lit double + lit simple" }
room_origan = Room.find_or_create_by!(code: "ORI") { |r| r.name = "Origan"; r.level = 2; r.description = "2 lits simples adaptables en lit double + lit superposé" }
room_laurier = Room.find_or_create_by!(code: "MEZ") { |r| r.name = "Laurier (mezzanine)"; r.level = 2; r.description = "2 lits simples" }
room_grassland = Room.find_or_create_by!(code: "PAT") { |r| r.name = "Pâture est"; r.level = -1; r.description = "Zone pour les tentes ⛺️" }
room_parking = Room.find_or_create_by!(code: "PKG") { |r| r.name = "Parking"; r.level = -1; r.description = "Zone pour les camping-cars et vans aménagés 🚐" }
room_tiny = Room.find_or_create_by!(code: "TNY") { |r| r.name = "Tiny house"; r.level = -1; r.description = "Tiny house" }

LodgingRoom.find_or_create_by!(lodging: lodging_8, room: room_romarin)
LodgingRoom.find_or_create_by!(lodging: lodging_8, room: room_balsamine)

LodgingRoom.find_or_create_by!(lodging: lodging_16, room: room_lavande)
LodgingRoom.find_or_create_by!(lodging: lodging_16, room: room_melisse)
LodgingRoom.find_or_create_by!(lodging: lodging_16, room: room_capucine)
LodgingRoom.find_or_create_by!(lodging: lodging_16, room: room_sarriette)
LodgingRoom.find_or_create_by!(lodging: lodging_16, room: room_origan)
LodgingRoom.find_or_create_by!(lodging: lodging_16, room: room_laurier)

LodgingRoom.find_or_create_by!(lodging: lodging_25, room: room_romarin)
LodgingRoom.find_or_create_by!(lodging: lodging_25, room: room_balsamine)
LodgingRoom.find_or_create_by!(lodging: lodging_25, room: room_lavande)
LodgingRoom.find_or_create_by!(lodging: lodging_25, room: room_melisse)
LodgingRoom.find_or_create_by!(lodging: lodging_25, room: room_capucine)
LodgingRoom.find_or_create_by!(lodging: lodging_25, room: room_sarriette)
LodgingRoom.find_or_create_by!(lodging: lodging_25, room: room_origan)
LodgingRoom.find_or_create_by!(lodging: lodging_25, room: room_laurier)

LodgingRoom.find_or_create_by!(lodging: lodging_tents, room: room_grassland)

LodgingRoom.find_or_create_by!(lodging: lodging_vans, room: room_parking)

# Le Grand-Duc est composé de La Hulotte + La Chevêche : réserver le composite
# bloque ses composants (et inversement), par calcul à la volée (PRD §11.4).
LodgingComposition.find_or_create_by!(composite_lodging: lodging_25, component_lodging: lodging_16)
LodgingComposition.find_or_create_by!(composite_lodging: lodging_25, component_lodging: lodging_8)

Space.find_or_create_by!(code: "TIL") { |s| s.name = "Tilleul"; s.description = "1er étage, 140 m2" }
Space.find_or_create_by!(code: "SAU") { |s| s.name = "Saule"; s.description = "1er étage, 45 m2" }
# « Les 2 salles » (code T+S) RETIRÉ (décision Michael 2026-07-20) : remplacé par
# la remise DUO automatique au devis (Grande + Petite salle le même jour). Voir
# rake spaces:convert_deux_salles pour la conversion de l'historique en prod.
Space.find_or_create_by!(code: "CUI") { |s| s.name = "Cuisine professionnelle" }
Space.find_or_create_by!(code: "CWK") { |s| s.name = "Coworking"; s.description = "Espace de travail avec écrans" }

jeanclaude = Human.find_or_create_by!(email: "jeanclaude@claudy.test") { |h| h.name = "Jean-Claude" }
User.find_or_create_by!(email: "jeanclaude@claudy.test") { |u| u.password = "secret"; u.human = jeanclaude }

miranda = Human.find_or_create_by!(email: "miranda@claudy.test") { |h| h.name = "Miranda" }
User.find_or_create_by!(email: "miranda@claudy.test") { |u| u.password = "secret"; u.human = miranda }

Team.find_or_create_by!(name: "Pole Technique")
Team.find_or_create_by!(name: "Pole Accueil")
Team.find_or_create_by!(name: "Pole Espaces verts")

project = Project.create(name: "Poulailler mobile", due_date: Date.today + 4.months, human: jeanclaude)

Task.create(
  name: "Faire les plans détaillés du poulailler", 
  project: project, 
  status: Task::STATUS_IN_PROGRESS,
  due_date: Date.today + 1.month,
  humans: [jeanclaude]
)
Task.create(
  name: "Réunir les matériaux nécessaires à la construction", 
  project: project, 
  status: Task::STATUS_OPEN,
  due_date: Date.today + 2.months,
  humans: [jeanclaude, miranda]
)
Task.create(
  name: "Construire le poulailler",
  project: project,
  status: Task::STATUS_OPEN,
  due_date: Date.today + 4.month,
  humans: [jeanclaude, miranda]
)

GatheringCategory.find_or_create_by!(name: "Popup Day") do |c|
  c.color = "emerald"
  c.default_start_time = "08:45"
  c.default_duration_minutes = 360
end
GatheringCategory.find_or_create_by!(name: "Chantier") do |c|
  c.color = "amber"
  c.default_start_time = "09:30"
  c.default_duration_minutes = 480
end
GatheringCategory.find_or_create_by!(name: "Conseil des Sourciers") do |c|
  c.color = "violet"
  c.default_start_time = "18:00"
  c.default_duration_minutes = 60
end
GatheringCategory.find_or_create_by!(name: "Mise au vert") do |c|
  c.color = "rose"
  c.default_start_time = "00:00"
  c.default_duration_minutes = 1440
end
GatheringCategory.find_or_create_by!(name: "Rencontre archis") do |c|
  c.color = "sky"
end

# Hamacs — RentalItems saisonniers (mai-octobre, tranche 2 funnel B2C)
RentalItem.find_or_create_by!(name: "Hamac simple") do |r|
  r.price_cents = 750   # 7,50 €/nuit — à ajuster via l'admin
  r.stock = 4
  r.description = "Hamac 1 personne, disponible de mai à octobre."
end
RentalItem.find_or_create_by!(name: "Hamac double") do |r|
  r.price_cents = 1_500 # 15 €/nuit — à ajuster via l'admin
  r.stock = 2
  r.description = "Hamac 2 personnes, disponible de mai à octobre."
end
