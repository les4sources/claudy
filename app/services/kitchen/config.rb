module Kitchen
  # Paramètres de l'offre de cuisine (epic #219, phase 2). Les prestations
  # dépendent de personnes : si plus personne ne s'en charge, la famille se
  # retire de l'offre depuis Paramètres > Cuisine, sans redéploiement.
  #
  # Toute lecture de ces réglages passe par ici — les clés `Setting` ne sont
  # jamais lues à la main ailleurs.
  module Config
    module_function

    # Ordre d'affichage de l'écran et des sélecteurs.
    FAMILIES = [
      { key: "repas",  label: "Repas",   hint: "Préparés par Stéphanie, validés par email." },
      { key: "buffet", label: "Buffets", hint: "Préparés par un membre du collectif, végé ou avec viande." },
      { key: "apero",  label: "Apéros",  hint: "Planche de produits locaux, préparée par un membre." }
    ].freeze

    # Plafonds et délais d'usage, ceux qu'on annonce aux clients aujourd'hui.
    # Ce sont des repères : ils avertissent, ils ne bloquent jamais (le SPW est
    # passé à 35 convives).
    DEFAULT_MAX_PEOPLE = { "repas" => 25 }.freeze
    DEFAULT_LEAD_DAYS  = { "repas" => 7, "buffet" => 5, "apero" => 5 }.freeze
    DEFAULT_COORDINATOR_EMAIL = "malau@les4sources.be".freeze

    def families = FAMILIES

    def family_keys = FAMILIES.map { |f| f[:key] }

    def family_label(family) = FAMILIES.find { |f| f[:key] == family.to_s }&.fetch(:label)

    # Activée par défaut : une installation neuve propose tout.
    def enabled?(family)
      Setting["kitchen.#{family}.enabled"] != "0"
    end

    def default_human(family)
      id = Setting["kitchen.#{family}.default_human_id"].presence
      id && Human.find_by(id: id)
    end

    # Une valeur EFFACÉE (ligne présente, valeur vide) veut dire « pas de
    # plafond » — distinct d'une clé jamais posée, qui retombe sur le défaut.
    def max_people(family) = setting_integer("kitchen.#{family}.max_people", DEFAULT_MAX_PEOPLE[family.to_s])

    def lead_days(family) = setting_integer("kitchen.#{family}.lead_days", DEFAULT_LEAD_DAYS[family.to_s])

    def coordinator_email
      Setting["kitchen.coordinator_email"].presence || DEFAULT_COORDINATOR_EMAIL
    end

    # Types proposables aujourd'hui, dans l'ordre du catalogue.
    def enabled_kinds
      MealOrder::KINDS.select { |kind| enabled?(MealOrder::KIND_FAMILIES[kind]) }
    end

    def setting_integer(key, fallback)
      raw = Setting[key]
      return fallback if raw.nil?

      Integer(raw, exception: false)
    end
  end
end
