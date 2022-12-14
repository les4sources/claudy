# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)

lodging_8 = Lodging.create(name: "La Chevêche", summary: "4 à 8 personnes")
lodging_16 = Lodging.create(name: "La Hulotte", summary: "9 à 16 personnes")
lodging_25 = Lodging.create(name: "Le Grand-Duc", summary: "17 à 25 personnes", party_hall_availability: true)

room_romarin = Room.create(name: "Romarin", level: 0, code: "ROM")
room_balsamine = Room.create(name: "Balsamine", level: 0, code: "BAL")
room_lavande = Room.create(name: "Lavande", level: 1, code: "LAV")
room_melisse = Room.create(name: "Mélisse", level: 1, code: "MEL")
room_capucine = Room.create(name: "Capucine", level: 1, code: "CAP")
room_sarriette = Room.create(name: "Sarriette", level: 2, code: "SAR")
room_origan = Room.create(name: "Origan", level: 2, code: "ORI")

LodgingRoom.create(lodging: lodging_8, room: room_romarin)
LodgingRoom.create(lodging: lodging_8, room: room_balsamine)

LodgingRoom.create(lodging: lodging_16, room: room_lavande)
LodgingRoom.create(lodging: lodging_16, room: room_melisse)
LodgingRoom.create(lodging: lodging_16, room: room_capucine)
LodgingRoom.create(lodging: lodging_16, room: room_sarriette)
LodgingRoom.create(lodging: lodging_16, room: room_origan)

LodgingRoom.create(lodging: lodging_25, room: room_romarin)
LodgingRoom.create(lodging: lodging_25, room: room_balsamine)
LodgingRoom.create(lodging: lodging_25, room: room_lavande)
LodgingRoom.create(lodging: lodging_25, room: room_melisse)
LodgingRoom.create(lodging: lodging_25, room: room_capucine)
LodgingRoom.create(lodging: lodging_25, room: room_sarriette)
LodgingRoom.create(lodging: lodging_25, room: room_origan)
