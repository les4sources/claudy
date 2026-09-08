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

    # Salles & cuisine pro — tarifs semaine.
    # Source de vérité : https://www.les4sources.be/sejours/tarifs (relevé le
    # 2026-09-06, epic #234 décision 3). Périodes :
    # "journee" | "soiree" | "journee_et_soiree".
    #
    # `journee_et_soiree` = journée + « forfait soir » du site (prolongation
    # jusqu'à 23 h) : petite +30, grande +60, les deux salles +90. La cuisine pro
    # n'a PAS de forfait soir sur le site — sa journée + soirée vaut sa journée.
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
        "journee_et_soiree" => 11_000   # 110 — pas de forfait soir cuisine
      }.freeze,
      # Remise DUO (décision Michael 2026-07-20, reprise par l'epic #234
      # décision 6) : Grande Salle ET Petite Salle le MÊME jour, la MÊME période,
      # valent la colonne « Les deux salles » du site — forfaits compris.
      "deux_salles" => {
        "journee"           => 39_000,  # 390 € (au lieu de 290 + 140 = 430)
        "soiree"            => 25_000,  # 250 €
        "journee_et_soiree" => 48_000   # 390 + forfait soir 90 €
      }.freeze
    }.freeze

    # Tarifs week-end : soirée du vendredi, samedi et dimanche (epic #234
    # décision 4 — la JOURNÉE du vendredi reste en semaine, le site ouvrant le
    # week-end à 18h30). La classification vit dans `Pricing::HallGrid`.
    HALL_RATES_WEEKEND = {
      "grande_salle" => {
        "journee"           => 38_000,  # 380 €
        "soiree"            => 25_000,  # 250 €
        "journee_et_soiree" => 45_500   # 380 + forfait soir 75 €
      }.freeze,
      "petite_salle" => {
        "journee"           => 19_000,  # 190 €
        "soiree"            => 12_000,  # 120 €
        "journee_et_soiree" => 23_000   # 190 + forfait soir 40 €
      }.freeze,
      "cuisine_pro" => {
        "journee"           => 15_000,  # 150 €
        "soiree"            =>  9_500,  # 95 €
        "journee_et_soiree" => 15_000   # 150 — pas de forfait soir cuisine
      }.freeze,
      # Remise DUO week-end (cf. HALL_RATES["deux_salles"]).
      "deux_salles" => {
        "journee"           => 49_500,  # 495 € (au lieu de 380 + 190 = 570)
        "soiree"            => 33_500,  # 335 €
        "journee_et_soiree" => 61_000   # 495 + forfait soir 115 €
      }.freeze
    }.freeze

    # Forfaits multi-jours du site (epic #234 phase 2). Ils portent la JOURNÉE
    # des jours couverts ; une soirée ajoutée par-dessus se facture au « forfait
    # soir » de la grille du jour (dérivé : journée + soirée − journée).
    #
    # Semaine : « 2 jours » (deux jours consécutifs) et « 5 jours » (la semaine
    # complète, retenue dès 3 jours consécutifs entre lundi et vendredi quand
    # elle est moins chère).
    HALL_PACKAGES = {
      "grande_salle" => { "deux_jours" =>  54_000, "cinq_jours" =>  99_000 }.freeze,
      "petite_salle" => { "deux_jours" =>  27_000, "cinq_jours" =>  52_500 }.freeze,
      "cuisine_pro"  => { "deux_jours" =>  21_000, "cinq_jours" =>  32_000 }.freeze,
      "deux_salles"  => { "deux_jours" =>  75_000, "cinq_jours" => 140_000 }.freeze
    }.freeze

    # Week-end : « 2 jours » et le forfait « du vendredi 18h30 au dimanche soir ».
    HALL_PACKAGES_WEEKEND = {
      "grande_salle" => { "deux_jours" => 72_000, "forfait_weekend" => 79_000 }.freeze,
      "petite_salle" => { "deux_jours" => 36_000, "forfait_weekend" => 39_000 }.freeze,
      "cuisine_pro"  => { "deux_jours" => 28_500, "forfait_weekend" => 29_000 }.freeze,
      "deux_salles"  => { "deux_jours" => 94_000, "forfait_weekend" => 99_000 }.freeze
    }.freeze

    # Alias rétrocompatible — rate du forfait journée par kind.
    HALL_PER_DAY_CENTS = HALL_RATES.transform_values { |r| r["journee"] }.freeze

    # Cuisine : €/pers (epic Cuisine #219). Les libellés vivent dans
    # `MealOrder::KIND_LABELS` — source unique pour les vues comme pour le seed.
    MEAL_PER_PERSON_CENTS = {
      "repas"         => 1_500, # un repas, midi ou soir
      "trio"          => 3_500, # midi + goûter + soir
      "buffet_vege"   => 1_200,
      "buffet_viande" => 1_400,
      "apero"         => 500    # provisoire, à ajuster dans Paramètres > Tarifs
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

    # ------------------------------------------------------------------
    # Façade de lecture (issue #124) : BASE D'ABORD, constantes en repli.
    #
    # Chaque accesseur ci-dessous interroge `Pricing::Rates` (table `rates`,
    # mémoïsée pour la requête) puis retombe sur la constante codée juste
    # au-dessus quand la clé n'est pas paramétrée. Les constantes restent la
    # source du seed (`rake rates:seed_from_catalog`) et le filet de sécurité :
    # à barème identique en base, aucun devis ne bouge.
    #
    # Les consommateurs (PricingModel, drafts, vues) DOIVENT passer par ces
    # méthodes et non plus lire les constantes directement.
    # ------------------------------------------------------------------

    # Slug de clé stable pour un nom d'hébergement ("La Chevêche" → la_cheveche).
    def lodging_key(name)
      I18n.transliterate(name.to_s).tr("-", " ").parameterize(separator: "_")
    end

    # Prix d'un pack de coworking — table `rates` (issue #124) d'abord,
    # constante en repli, comme le reste de la façade.
    def coworking_pack_cents(days)
      fallback = COWORKING_PACKS[days.to_i]
      return nil if fallback.nil?

      Pricing::Rates.cents_or("coworking.pack_#{days.to_i}", fallback)
    end

    def default_deposit_rate
      Pricing::Rates.rate_or("deposit.default_rate", DEFAULT_DEPOSIT_RATE)
    end

    def dog_supplement_cents
      Pricing::Rates.cents_or("dog.supplement", DOG_SUPPLEMENT_CENTS)
    end

    def camping_per_person_night_cents(kind)
      return nil unless CAMPING_PER_PERSON_NIGHT_CENTS.key?(kind.to_s)

      Pricing::Rates.cents_or("camping.#{kind}_per_person_night",
                              CAMPING_PER_PERSON_NIGHT_CENTS[kind.to_s])
    end

    def van_per_night_cents
      Pricing::Rates.cents_or("van.per_night", VAN_PER_NIGHT_CENTS)
    end

    def terrace_per_person_day_cents
      Pricing::Rates.cents_or("terrace.per_person_day", TERRACE_PER_PERSON_DAY_CENTS)
    end

    def meal_per_person_cents(kind)
      return nil unless MEAL_PER_PERSON_CENTS.key?(kind.to_s)

      Pricing::Rates.cents_or("meal.#{kind}.per_person", MEAL_PER_PERSON_CENTS[kind.to_s])
    end

    def meal_kinds
      MEAL_PER_PERSON_CENTS.keys
    end

    def pizza_party_base_cents
      Pricing::Rates.cents_or("pizza_party.base", PIZZA_PARTY_BASE_CENTS)
    end

    def pizza_party_per_person_cents
      Pricing::Rates.cents_or("pizza_party.per_person", PIZZA_PARTY_PER_PERSON_CENTS)
    end

    # Barème d'un espace pour une période, tarif semaine ou week-end.
    # Retourne nil si l'espace ou la période n'existe pas au catalogue.
    def hall_rate_cents(kind, period, weekend: false)
      # Un espace sans grille week-end retombe sur son tarif semaine (parité
      # avec le comportement historique de PricingModel).
      weekend  = weekend && HALL_RATES_WEEKEND.key?(kind.to_s)
      table    = weekend ? HALL_RATES_WEEKEND : HALL_RATES
      fallback = table.dig(kind.to_s, period.to_s)
      return nil if fallback.nil?

      Pricing::Rates.cents_or(hall_key(kind, period, weekend: weekend), fallback)
    end

    # Montant d'un forfait multi-jours (« deux_jours », « cinq_jours »,
    # « forfait_weekend »), table `rates` d'abord comme le reste de la façade.
    # Retourne nil quand le forfait n'existe pas pour cet espace / cette grille.
    def hall_package_cents(kind, package, weekend: false)
      table    = weekend ? HALL_PACKAGES_WEEKEND : HALL_PACKAGES
      fallback = table.dig(kind.to_s, package.to_s)
      return nil if fallback.nil?

      Pricing::Rates.cents_or(hall_key(kind, package, weekend: weekend), fallback)
    end

    # « Forfait soir » du site : le supplément qui prolonge une journée jusqu'à
    # 23 h. Dérivé du barème plutôt que stocké — il vaut exactement l'écart entre
    # « journée + soirée » et « journée » (0 pour la cuisine pro).
    def hall_evening_supplement_cents(kind, weekend: false)
      day  = hall_rate_cents(kind, "journee", weekend: weekend)
      both = hall_rate_cents(kind, "journee_et_soiree", weekend: weekend)
      return 0 if day.nil? || both.nil?

      [both - day, 0].max
    end

    # true si l'espace existe au catalogue (semaine — référence structurelle).
    def hall_kind?(kind)
      HALL_RATES.key?(kind.to_s)
    end

    def hall_key(kind, period, weekend: false)
      "#{weekend ? 'hall_weekend' : 'hall'}.#{kind}.#{period}"
    end

    def lodging_rate(name)
      base = LODGING_RATES[name]
      return nil if base.nil?

      slug = lodging_key(name)
      Pricing::LodgingRate.new(
        name: base.name,
        first_night_cents: Pricing::Rates.cents_or("lodging.#{slug}.first_night",
                                                   base.first_night_cents),
        extra_night_cents: Pricing::Rates.cents_or("lodging.#{slug}.extra_night",
                                                   base.extra_night_cents),
        named_packages: base.named_packages.to_h { |nights, package|
          [nights, package.merge(
            amount_cents: Pricing::Rates.cents_or("lodging.#{slug}.package_#{nights}",
                                                  package[:amount_cents])
          )]
        }
      )
    end

    # Prix d'un hamac (RentalItem) pour une nuit. Tarif paramétré d'abord, puis
    # lookup RentalItem, puis fallback sur HAMAC_FALLBACK_CENTS.
    def hamac_rate(kind)
      configured = Pricing::Rates.cents("hamac.#{kind}")
      return configured if configured

      db_name = kind.to_s == "double" ? "Hamac double" : "Hamac simple"
      RentalItem.find_by(name: db_name)&.price_cents || HAMAC_FALLBACK_CENTS[kind.to_s]
    end
  end
end
