module Pricing
  # Registre central des barèmes — paramétré, jamais hardcodé en vue (AC-T2-16).
  # Source unique des prix de la tranche 2 (structures observées chez Malau,
  # cf. PRD §3.2 + matrice ISA section G). Tous les montants sont TVAC, en cents.
  #
  # Les barèmes hébergement utilisent la formule fermée dégressive + forfaits
  # nommés (Q3 hybride). Les autres structures (camping €/pers/nuit, salle au
  # forfait, repas €/pers, Pizza Party forfait + €/pers, van forfait/nuit) sont
  # exposées comme tarifs unitaires consommés par PricingModel.
  module Catalog
    module_function

    # Part de l'acompte par défaut (Q : acompte 50 % configurable, AC-T2-16).
    DEFAULT_DEPOSIT_RATE = 0.5

    # Supplément chien standardisé (Q2) : 50 € / chien / séjour, plafonné à un
    # seul chien dans le flow auto (multi-chiens hors flow, traité par Malau).
    DOG_SUPPLEMENT_CENTS = 5_000

    # Barèmes hébergement par nom canonique de Lodging.
    LODGING_RATES = {
      "Le Grand-Duc" => Pricing::LodgingRate.new(
        name: "Le Grand-Duc",
        first_night_cents: 75_000,   # nuit 1 = 750 €
        extra_night_cents: 60_000,   # nuits suivantes = 600 €
        named_packages: {
          7 => { label: "forfait semaine", amount_cents: 241_000 } # 2 410 €
        }
      ),
      "La Hulotte" => Pricing::LodgingRate.new(
        name: "La Hulotte",
        first_night_cents: 48_500,   # 1 nuit semaine ≈ 485 €
        extra_night_cents: 26_000
      ),
      "La Chevêche" => Pricing::LodgingRate.new(
        name: "La Chevêche",
        first_night_cents: 27_500,   # 1 nuit 260-275 €
        extra_night_cents: 20_000,
        named_packages: {
          3 => { label: "forfait 3 nuits", amount_cents: 67_500 } # 675 €
        }
      ),
      "Tiny house" => Pricing::LodgingRate.new(
        name: "Tiny house",
        first_night_cents: 7_000,    # 70 €/nuit, linéaire
        extra_night_cents: 7_000
      )
    }.freeze

    # Camping / bivouac : €/pers/nuit (tente uniquement — hamac géré via RentalItem).
    CAMPING_PER_PERSON_NIGHT_CENTS = {
      "tente" => 750  # 7,50 €/pers/nuit
    }.freeze

    # Hamacs (RentalItem) : prix/nuit/unité, lookup DB avec fallback.
    # Disponibles mai-octobre ; les objets physiques sont dans rental_items.
    HAMAC_FALLBACK_CENTS = {
      "simple" => 750,   # 7,50 €/nuit fallback si RentalItem absent
      "double" => 1_500  # 15 €/nuit fallback
    }.freeze

    # Van / camping-car : forfait/nuit/véhicule.
    VAN_PER_NIGHT_CENTS = 1_500 # 15 €/nuit

    # Salles & cuisine pro : tarifs par période, base semaine TVAC 0%.
    # Source : https://www.les4sources.be/sejours/tarifs (tarifs semaine)
    # Périodes : "journee" | "soiree" | "journee_et_soiree"
    HALL_RATES = {
      "grande_salle" => {
        "journee"           => 29_000,  # 290 €
        "soiree"            => 19_000,  # 190 €
        "journee_et_soiree" => 35_000   # 290 + forfait soir 60 €
      }.freeze,
      "petite_salle" => {
        "journee"           => 14_000,  # 140 €
        "soiree"            =>  9_000,  # 90 €
        "journee_et_soiree" => 17_000   # 140 + forfait soir 30 €
      }.freeze,
      "cuisine_pro" => {
        "journee"           => 11_000,  # 110 €
        "soiree"            =>  7_000,  # 70 €
        "journee_et_soiree" => 14_000   # 110 + soirée estimée
      }.freeze
    }.freeze

    # Alias rétrocompatible — rate du forfait journée par kind.
    HALL_PER_DAY_CENTS = HALL_RATES.transform_values { |r| r["journee"] }.freeze

    # Repas : €/pers.
    MEAL_PER_PERSON_CENTS = {
      "repas_vege_midi" => 1_500, # 15 €/pers
      "buffet"          => 1_200, # buffet pain-fromages 12 €/pers
      "formule_complete" => 3_500 # 35 €/pers/jour
    }.freeze

    # Pizza Party : forfait + €/pers (40 € allumage + 7 €/pers patons).
    PIZZA_PARTY_BASE_CENTS = 4_000
    PIZZA_PARTY_PER_PERSON_CENTS = 700

    def lodging_rate(name)
      LODGING_RATES[name]
    end

    # Prix d'un hamac (RentalItem) pour une nuit. Lookup DB d'abord, fallback
    # sur HAMAC_FALLBACK_CENTS si le RentalItem n'est pas encore seedé.
    def hamac_rate(kind)
      db_name = kind.to_s == "double" ? "Hamac double" : "Hamac simple"
      RentalItem.find_by(name: db_name)&.price_cents || HAMAC_FALLBACK_CENTS[kind.to_s]
    end
  end
end
