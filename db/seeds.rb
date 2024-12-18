# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)

#lodging_8 = Lodging.create(name: "La Chevêche", summary: "4 à 8 personnes", price_night: 240)
lodging_8 = Lodging.find_or_create_by(name: 'La Chevêche') do |lodging|
  lodging.name = 'La Chevêche'
  lodging.summary = '4 à 8 personnes'
  lodging.price_night = '240'
end
lodging_16 = Lodging.find_or_create_by(name: 'La Hulotte') do |lodging|
  lodging.name = 'La Hulotte'
  lodging.summary = '9 à 16 personnes'
  lodging.price_night = '480'
end
lodging_25 = Lodging.find_or_create_by(name: 'Le Grand-Duc') do |lodging|
  lodging.name = 'Le Grand-Duc'
  lodging.summary = '17 à 25 personnes'
  lodging.price_night = '750'
  lodging.party_hall_availability = true
end
#lodging_16 = Lodging.create(name: "La Hulotte", summary: "9 à 16 personnes", price_night: 480)
#lodging_25 = Lodging.create(name: "Le Grand-Duc", summary: "17 à 25 personnes", price_night: 750, party_hall_availability: true)

room_romarin = Room.create(name: "Romarin", level: 0, code: "ROM", description: "2 lits simples adaptables en lit double + lit superposé")
room_balsamine = Room.create(name: "Balsamine", level: 0, code: "BAL", description: "2 lits simples adaptables en lit double + lit superposé")
room_lavande = Room.create(name: "Lavande", level: 1, code: "LAV", description: "2 lits simples adaptables en lit double")
room_melisse = Room.create(name: "Mélisse", level: 1, code: "MEL", description: "3 lits simples")
room_capucine = Room.create(name: "Capucine", level: 1, code: "CAP", description: "3 lits simples")
room_sarriette = Room.create(name: "Sarriette", level: 2, code: "SAR", description: "2 lits simples adaptables en lit double + lit simple")
room_origan = Room.create(name: "Origan", level: 2, code: "ORI", description: "2 lits simples adaptables en lit double + lit superposé")
room_laurier = Room.create(name: "Laurier (mezzanine)", level: 2, code: "MEZ", description: "2 lits simples")

room_balsamine = Room.find_or_create_by(code: 'BAL') do |room|
  room.name = 'Balsamine'
  room.level = 0
  room.code = 'BAL'
  room.description = 'lit double + lit superposé"'
end

room_lavande = Room.find_or_create_by(code: 'LAV') do |room|
  room.name = 'Lavande'
  room.level = 1
  room.code = 'LAV'
  room.description = '2 lits simples'
end

room_melisse = Room.find_or_create_by(code: 'MEL') do |room|
  room.name = 'Melisse'
  room.level = 1
  room.code = 'MEL'
  room.description = '3 lits simples'
end

room_capucine = Room.find_or_create_by(code: 'CAP') do |room|
  room.name = 'Capucine'
  room.level = 1
  room.code = 'CAP'
  room.description = '3 lits simples'
end

room_sarriette = Room.find_or_create_by(code: 'SAR') do |room|
  room.name = 'Sarriette'
  room.level = 2
  room.code = 'SAR'
  room.description = 'lit double + lit simple'
end

room_origan = Room.find_or_create_by(code: 'ORI') do |room|
  room.name = 'Origan'
  room.level = 2
  room.code = 'ORI'
  room.description = 'lit double + lit superposé'
end

room_laurier = Room.find_or_create_by(code: 'MEZ') do |room|
  room.name = 'Laurier (mezzanine)'
  room.level = 2
  room.code = 'MEZ'
  room.description = '2 lits simples'
end
#room_romarin = Room.create(name: "Romarin", level: 0, code: "ROM", description: "lit double + lit superposé")
#room_balsamine = Room.create(name: "Balsamine", level: 0, code: "BAL", description: "lit double + lit superposé")
#room_lavande = Room.create(name: "Lavande", level: 1, code: "LAV", description: "2 lits simples")
#room_melisse = Room.create(name: "Mélisse", level: 1, code: "MEL", description: "3 lits simples")
#room_capucine = Room.create(name: "Capucine", level: 1, code: "CAP", description: "3 lits simples")
#room_sarriette = Room.create(name: "Sarriette", level: 2, code: "SAR", description: "lit double + lit simple")
#room_origan = Room.create(name: "Origan", level: 2, code: "ORI", description: "lit double + lit superposé")
#room_laurier = Room.create(name: "Laurier (mezzanine)", level: 2, code: "MEZ", description: "2 lits simples")


Bed.find_or_create_by(name: 'Lit 1') do |bed|
  bed.name = "Lit 1"
  bed.description = "double"
  bed.price_cents = 500
  bed.room = room_romarin
end
Bed.find_or_create_by(name: 'Lit 2') do |bed|
  bed.name = "Lit 2"
  bed.description = "superposé"
  bed.price_cents = 500
  bed.room = room_romarin
end

Bed.find_or_create_by(name: 'Lit 3') do |bed|
  bed.name = "Lit 3"
  bed.description = "double"
  bed.price_cents = 500
  bed.room = room_balsamine
end
Bed.find_or_create_by(name: 'Lit 4') do |bed|
  bed.name = "Lit 4"
  bed.description = "superposé"
  bed.price_cents = 500
  bed.room = room_balsamine
end

Bed.find_or_create_by(name: 'Lit 5') do |bed|
  bed.name = "Lit 5"
  bed.description = "simple"
  bed.price_cents = 500
  bed.room = room_lavande
end
Bed.find_or_create_by(name: 'Lit 6') do |bed|
  bed.name = "Lit 6"
  bed.description = "simple"
  bed.price_cents = 500
  bed.room = room_lavande
end

Bed.find_or_create_by(name: 'Lit 7') do |bed|
  bed.name = "Lit 7"
  bed.description = "simple"
  bed.price_cents = 500
  bed.room = room_melisse
end
Bed.find_or_create_by(name: 'Lit 8') do |bed|
  bed.name = "Lit 8"
  bed.description = "simple"
  bed.price_cents = 500
  bed.room = room_melisse
end
Bed.find_or_create_by(name: 'Lit 9') do |bed|
  bed.name = "Lit 9"
  bed.description = "simple"
  bed.price_cents = 500
  bed.room = room_melisse
end
Bed.find_or_create_by(name: 'Lit 10') do |bed|
  bed.name = "Lit 10"
  bed.description = "simple"
  bed.price_cents = 500
  bed.room = room_capucine
end
Bed.find_or_create_by(name: 'Lit 11') do |bed|
  bed.name = "Lit 11"
  bed.description = "simple"
  bed.price_cents = 500
  bed.room = room_capucine
end
Bed.find_or_create_by(name: 'Lit 12') do |bed|
  bed.name = "Lit 12"
  bed.description = "simple"
  bed.price_cents = 500
  bed.room = room_capucine
end

Bed.find_or_create_by(name: 'Lit 13') do |bed|
  bed.name = "Lit 13"
  bed.description = "simple"
  bed.price_cents = 500
  bed.room = room_sarriette
end
Bed.find_or_create_by(name: 'Lit 14') do |bed|
  bed.name = "Lit 14"
  bed.description = "double"
  bed.price_cents = 500
  bed.room = room_sarriette
end

Bed.find_or_create_by(name: 'Lit 15') do |bed|
  bed.name = "Lit 15"
  bed.description = "double"
  bed.price_cents = 500
  bed.room = room_origan
end
Bed.find_or_create_by(name: 'Lit 16') do |bed|
  bed.name = "Lit 16"
  bed.description = "superposé"
  bed.price_cents = 500
  bed.room = room_origan
end

Bed.find_or_create_by(name: 'Lit 17') do |bed|
  bed.name = "Lit 17"
  bed.description = "simple"
  bed.price_cents = 500
  bed.room = room_laurier
end
Bed.find_or_create_by(name: 'Lit 18') do |bed|
  bed.name = "Lit 18"
  bed.description = "simple"
  bed.price_cents = 500
  bed.room = room_laurier
end




LodgingRoom.find_or_create_by(lodging: lodging_8, room: room_romarin) do |lr|
  lr.room = room_romarin
  lr.lodging = lodging_8
end
LodgingRoom.find_or_create_by(lodging: lodging_8,room: room_balsamine) do |lr|
  lr.room = room_balsamine
  lr.lodging = lodging_8
end

#LodgingRoom.create(lodging: lodging_8, room: room_romarin)
#LodgingRoom.create(lodging: lodging_8, room: room_balsamine)

LodgingRoom.find_or_create_by(lodging: lodging_16, room: room_lavande) do |lr|
  lr.room = room_lavande
  lr.lodging = lodging_16
end
LodgingRoom.find_or_create_by(lodging: lodging_16,room: room_melisse) do |lr|
  lr.room = room_melisse
  lr.lodging = lodging_16
end
LodgingRoom.find_or_create_by(lodging: lodging_16, room: room_capucine) do |lr|
  lr.room = room_capucine
  lr.lodging = lodging_16
end
LodgingRoom.find_or_create_by(lodging: lodging_16,room: room_sarriette) do |lr|
  lr.room = room_sarriette
  lr.lodging = lodging_16
end
LodgingRoom.find_or_create_by(lodging: lodging_16, room: room_origan) do |lr|
  lr.room = room_origan
  lr.lodging = lodging_16
end

#LodgingRoom.find_or_create_by(lodging: lodging_16,room: room_laurier) do |lr|
#  lr.room = room_laurier
#  lr.lodging = lodging_16
#end

#LodgingRoom.create(lodging: lodging_16, room: room_lavande)
#LodgingRoom.create(lodging: lodging_16, room: room_melisse)
#LodgingRoom.create(lodging: lodging_16, room: room_capucine)
#LodgingRoom.create(lodging: lodging_16, room: room_sarriette)
#LodgingRoom.create(lodging: lodging_16, room: room_origan)
#LodgingRoom.create(lodging: lodging_16, room: room_laurier)

LodgingRoom.find_or_create_by(lodging: lodging_25,room: room_romarin) do |lr|
  lr.room = room_romarin
  lr.lodging = lodging_25
end
LodgingRoom.find_or_create_by(lodging: lodging_25,room: room_balsamine) do |lr|
  lr.room = room_balsamine
  lr.lodging = lodging_25
end
LodgingRoom.find_or_create_by(lodging: lodging_25,room: room_lavande) do |lr|
  lr.room = room_lavande
  lr.lodging = lodging_25
end
LodgingRoom.find_or_create_by(lodging: lodging_25,room: room_melisse) do |lr|
  lr.room = room_melisse
  lr.lodging = lodging_25
end
LodgingRoom.find_or_create_by(lodging: lodging_25,room: room_capucine) do |lr|
  lr.room = room_capucine
  lr.lodging = lodging_25
end
LodgingRoom.find_or_create_by(lodging: lodging_25,room: room_sarriette) do |lr|
  lr.room = room_sarriette
  lr.lodging = lodging_25
end
LodgingRoom.find_or_create_by(lodging: lodging_25,room: room_origan) do |lr|
  lr.room = room_origan
  lr.lodging = lodging_25
end
#LodgingRoom.find_or_create_by(lodging: lodging_25,room: room_laurier) do |lr|
#  lr.room = room_laurier
#  lr.lodging = lodging_25
#end
#LodgingRoom.create(lodging: lodging_25, room: room_romarin)
#LodgingRoom.create(lodging: lodging_25, room: room_balsamine)
#LodgingRoom.create(lodging: lodging_25, room: room_lavande)
#LodgingRoom.create(lodging: lodging_25, room: room_melisse)
#LodgingRoom.create(lodging: lodging_25, room: room_capucine)
#LodgingRoom.create(lodging: lodging_25, room: room_sarriette)
#LodgingRoom.create(lodging: lodging_25, room: room_origan)
#LodgingRoom.create(lodging: lodging_25, room: room_laurier)


Space.find_or_create_by(code: 'TIL') do |space|
  space.name = 'Tilleul'
  space.code = 'TIL'
  space.description = '1er étage, 140 m2'
end
Space.find_or_create_by(code: 'SAU') do |space|
  space.name = 'Saule'
  space.code = 'SAU'
  space.description = '1er étage, 45 m2'
end
Space.find_or_create_by(code: 'T+S') do |space|
  space.name = 'Les 2 salles'
  space.code = 'T+S'
  space.description = '1er étage, 185 m2'
end
Space.find_or_create_by(code: 'CHE') do |space|
  space.name = 'Chêne'
  space.code = 'CHE'
  space.description = '2ème étage, 45 m2'
end
Space.find_or_create_by(code: 'CUI') do |space|
  space.name = 'Cuisine professionnelle'
  space.code = 'CUI'
end
Space.find_or_create_by(code: 'CHA') do |space|
  space.name = 'Chambre froide'
  space.code = 'CHA'
end
#Space.create(name: "Tilleul", code: "TIL", description: "1er étage, 140 m2")
#Space.create(name: "Saule", code: "SAU", description: "1er étage, 45 m2")
#Space.create(name: "Les 2 salles", code: "T+S", description: "1er étage, 185 m2")
#Space.create(name: "Chêne", code: "CHE", description: "2ème étage, 45 m2")
#Space.create(name: "Cuisine professionnelle", code: "CUI")
#Space.create(name: "Chambre froide", code: "CHA")


#jeanclaude = Human.find_or_create_by(email: "jeanclaude@claudy.test") do |human|
#  human.name = "Jean-Claude"
#  human.email = "jeanclaude@claudy.test"
#end
#User.find_or_create_by(email: "jeanclaude@claudy.test") do |user|
#  user.password = "secret"
#  user.human = jeanclaude
#  user.email = "jeanclaude@claudy.test"
#end

#miranda = Human.find_or_create_by(email: "jmiranda@claudy.test") do |human|
#  human.name = "Miranda"
#  human.email = "miranda@claudy.test"
#end
#User.find_or_create_by(email: "jeanclaude@claudy.test") do |user|
#  user.password = "secret"
#  user.human = miranda
#  user.email = "miranda@claudy.test"
#end

#jeanclaude = Human.create(name: "Jean-Claude", email: "jeanclaude@claudy.test")
#User.create(email: "jeanclaude@claudy.test", password: "secret", human: jeanclaude)

#miranda = Human.create(name: "Miranda", email: "miranda@claudy.test")
#User.create(email: "miranda@claudy.test", password: "secret", human: miranda)

#Team.find_or_create_by(name: "Pole Technique") do |team|
#  team.name = "Pole Technique"
#end
#Team.find_or_create_by(name: "Pole Accueil") do |team|
#  team.name = "Pole Accueil"
#end
#Team.find_or_create_by(name: "Pole Espaces verts") do |team|
#  team.name = "Pole Espaces verts"
#end
#Team.create(name: "Pole Technique")
#Team.create(name: "Pole Accueil")
#Team.create(name: "Pole Espaces verts")


#project = Project.find_or_create_by(name: "Poulailler mobile") do |project|
#  project.name = ""
#  project.human = jeanclaude
#  project.due_date = Date.today + 4.months
#end

#project = Project.create(name: "Poulailler mobile", due_date: Date.today + 4.months, human: jeanclaude)

#Task.find_or_create_by(name: "Faire les plans détaillés du poulailler") do |task|
# task.name = "Faire les plans détaillés du poulailler"
# task.project = project
# task.status = Task::STATUS_IN_PROGRESS
# task.due_date = Date.today + 1.month
# task.humans = [jeanclaude]
#end

#Task.find_or_create_by(name: "Réunir les matériaux nécessaires à la construction") do |task|
# task.name = "Réunir les matériaux nécessaires à la construction"
# task.project = project
# task.status = Task::STATUS_OPEN
# task.due_date = Date.today + 2.month
# task.humans = [jeanclaude, miranda]
#end

#Task.find_or_create_by(name: "Construire le poulailler") do |task|
# task.name = "Construire le poulailler"
# task.project = project
# task.status = Task::STATUS_OPEN
# task.due_date = Date.today + 4.month
# task.humans = [jeanclaude, miranda]
#end

#Task.create(
#  name: "Faire les plans détaillés du poulailler", 
#  project: project, 
#  status: Task::STATUS_IN_PROGRESS,
#  due_date: Date.today + 1.month,
#  humans: [jeanclaude]
#)
#Task.create(
#  name: "Réunir les matériaux nécessaires à la construction", 
#  project: project, 
#  status: Task::STATUS_OPEN,
#  due_date: Date.today + 2.months,
#  humans: [jeanclaude, miranda]
#)
#Task.create(
#  name: "Construire le poulailler", 
#  project: project, 
#  status: Task::STATUS_OPEN,
#  due_date: Date.today + 4.month,
#  humans: [jeanclaude, miranda]
#)
