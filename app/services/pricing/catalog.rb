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

    # Terrasse : forfait €/pers/JOUR (occupation d'un jour, ex. BBQ de randonneurs).
    # ADMIN UNIQUEMENT — jamais proposé sur le funnel public (décision Michael,
    # 2026-07-20). Persisté en `CampingBooking` de `kind: "terrasse"`, un par jour.
    TERRACE_PER_PERSON_DAY_CENTS = 250 # 2,50 €/pers/jour

    # Salles & cuisine pro — tarifs semaine (lun-jeu + ven journée).
    # Source : https://www.les4sources.be/sejours/tarifs
    # Périodes : "journee" | "soiree" | "journee_et_soiree"
    HALL_RATES = {
      "grande_salle" => {
        "journee"           => 29_000,  # 290 €
        "soiree"            => 19_000,  # 190 €
        "journee_et_soiree" => 38_000   # 290 + extension soirée 90 €
      }.freeze,
      "petite_salle" => {
        "journee"           => 14_000,  # 140 €
        "soiree"            =>  9_000,  # 90 €
        "journee_et_soiree" => 20_000   # 140 + extension soirée 60 €
      }.freeze,
      "cuisine_pro" => {
        "journee"           => 11_000,  # 110 €
        "soiree"            =>  7_000,  # 70 €
        "journee_et_soiree" => 14_000   # 110 + extension soirée 30 €
      }.freeze,
      # Remise DUO (décision Michael 2026-07-20) : quand Grande Salle ET Petite
      # Salle sont louées le MÊME jour, la MÊME période, un tarif duo remplace la
      # somme des deux (< somme). L'ancien espace « Les 2 salles » disparaît au
      # profit de cette remise automatique. Journée+soirée = jour duo + 150 €
      # (extensions soirée des deux salles : 90 + 60).
      "deux_salles" => {
        "journee"           => 39_000,  # 390 € (au lieu de 290 + 140 = 430)
        "soiree"            => 25_000,  # 250 €
        "journee_et_soiree" => 54_000   # 390 + 150 = 540 €
      }.freeze
    }.freeze

    # Tarifs week-end (ven soir + sam + dim). Vendredi soir = début week-end.
    # En B2C, wday=5 (vendredi) et wday=6 (samedi) → tarifs week-end.
    HALL_RATES_WEEKEND = {
      "grande_salle" => {
        "journee"           => 38_000,  # 380 €
        "soiree"            => 25_000,  # 250 €
        "journee_et_soiree" => 47_000   # 380 + extension soirée 90 €
      }.freeze,
      "petite_salle" => {
        "journee"           => 19_000,  # 190 €
        "soiree"            => 12_000,  # 120 €
        "journee_et_soiree" => 25_000   # 190 + extension soirée 60 €
      }.freeze,
      "cuisine_pro" => {
        "journee"           => 15_000,  # 150 €
        "soiree"            =>  9_500,  # 95 €
        "journee_et_soiree" => 18_000   # 150 + extension soirée 30 €
      }.freeze,
      # Remise DUO week-end (cf. HALL_RATES["deux_salles"]).
      "deux_salles" => {
        "journee"           => 49_500,  # 495 € (au lieu de 380 + 190 = 570)
        "soiree"            => 33_500,  # 335 €
        "journee_et_soiree" => 64_500   # 495 + 150 = 645 €
      }.freeze
    }.freeze

    # Alias rétrocompatible — rate du forfait journée par kind.
    HALL_PER_DAY_CENTS = HALL_RATES.transform_values { |r| r["journee"] }.freeze

    # Repas : €/pers.
    MEAL_PER_PERSON_CENTS = {
      "repas_vege_midi" => 1_500, # 15 €/pers
      "buffet"          => 1_200, # buffet pain-fromages 12 €/pers
    }.freeze

    # Pizza Party : forfait + €/pers (40 € allumage + 7 €/pers patons).
    PIZZA_PARTY_BASE_CENTS = 4_000
    PIZZA_PARTY_PER_PERSON_CENTS = 700

    # Packs de coworking (epic #126, Phase 1) : prix par nombre de journées.
    COWORKING_PACKS = {
      1  =>  2_000, # 20 €
      5  =>  8_000, # 80 €
      10 => 16_000, # 160 €
      20 => 30_000  # 300 €
    }.freeze

    # Prix d'un pack de coworking. La table `rates` (issue #124) gagne quand
    # elle existe et porte la clé ; sinon on retombe sur la constante ci-dessus.
    def coworking_pack_cents(days)
      fallback = COWORKING_PACKS[days.to_i]
      return nil if fallback.nil?

      configured_cents("coworking.pack_#{days.to_i}") || fallback
    end

    # Lecture défensive de la table `rates` : elle n'existe pas forcément encore
    # (l'issue #124 est un chantier parallèle), donc on ne la suppose jamais.
    def configured_cents(key)
      return nil unless defined?(Rate) && Rate.table_exists?

      Rate.find_by(key: key)&.amount_cents
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError,
           ActiveRecord::ConnectionNotEstablished
      nil
    end

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
