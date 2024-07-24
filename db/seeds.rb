# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)

lodging_8 = Lodging.create(name: "La Chevêche", summary: "4 à 8 personnes", price_night: 240)
lodging_16 = Lodging.create(name: "La Hulotte", summary: "9 à 16 personnes", price_night: 480)
lodging_25 = Lodging.create(name: "Le Grand-Duc", summary: "17 à 25 personnes", price_night: 750, party_hall_availability: true)

room_romarin = Room.create(name: "Romarin", level: 0, code: "ROM", description: "2 lits simples adaptables en lit double + lit superposé")
room_balsamine = Room.create(name: "Balsamine", level: 0, code: "BAL", description: "2 lits simples adaptables en lit double + lit superposé")
room_lavande = Room.create(name: "Lavande", level: 1, code: "LAV", description: "2 lits simples adaptables en lit double")
room_melisse = Room.create(name: "Mélisse", level: 1, code: "MEL", description: "3 lits simples")
room_capucine = Room.create(name: "Capucine", level: 1, code: "CAP", description: "3 lits simples")
room_sarriette = Room.create(name: "Sarriette", level: 2, code: "SAR", description: "2 lits simples adaptables en lit double + lit simple")
room_origan = Room.create(name: "Origan", level: 2, code: "ORI", description: "2 lits simples adaptables en lit double + lit superposé")
room_laurier = Room.create(name: "Laurier (mezzanine)", level: 2, code: "MEZ", description: "2 lits simples")

LodgingRoom.create(lodging: lodging_8, room: room_romarin)
LodgingRoom.create(lodging: lodging_8, room: room_balsamine)

LodgingRoom.create(lodging: lodging_16, room: room_lavande)
LodgingRoom.create(lodging: lodging_16, room: room_melisse)
LodgingRoom.create(lodging: lodging_16, room: room_capucine)
LodgingRoom.create(lodging: lodging_16, room: room_sarriette)
LodgingRoom.create(lodging: lodging_16, room: room_origan)
LodgingRoom.create(lodging: lodging_16, room: room_laurier)

LodgingRoom.create(lodging: lodging_25, room: room_romarin)
LodgingRoom.create(lodging: lodging_25, room: room_balsamine)
LodgingRoom.create(lodging: lodging_25, room: room_lavande)
LodgingRoom.create(lodging: lodging_25, room: room_melisse)
LodgingRoom.create(lodging: lodging_25, room: room_capucine)
LodgingRoom.create(lodging: lodging_25, room: room_sarriette)
LodgingRoom.create(lodging: lodging_25, room: room_origan)
LodgingRoom.create(lodging: lodging_25, room: room_laurier)

Space.create(name: "Tilleul", code: "TIL", description: "1er étage, 140 m2")
Space.create(name: "Saule", code: "SAU", description: "1er étage, 45 m2")
Space.create(name: "Les 2 salles", code: "T+S", description: "1er étage, 185 m2")
Space.create(name: "Chêne", code: "CHE", description: "2ème étage, 45 m2")
Space.create(name: "Cuisine professionnelle", code: "CUI")
Space.create(name: "Chambre froide", code: "CHA")

jeanclaude = Human.create(name: "Jean-Claude", email: "jeanclaude@claudy.test")
User.create(email: "jeanclaude@claudy.test", password: "secret", human: jeanclaude)

miranda = Human.create(name: "Miranda", email: "miranda@claudy.test")
User.create(email: "miranda@claudy.test", password: "secret", human: miranda)

Team.create(name: "Pole Technique")
Team.create(name: "Pole Accueil")
Team.create(name: "Pole Espaces verts")

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
