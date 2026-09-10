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

    # Les comptes de charge dédiés à la cuisine (epic #269, phase 1), posés par
    # `rake finance:seed_kitchen_accounts`. Deux comptes et non un : les repas et
    # les buffets sont deux économies différentes, tenues par des personnes
    # différentes, et le choix se fait une seule fois, à l'encodage.
    DEFAULT_EXPENSE_ACCOUNTS = {
      "600005" => "Achats cuisine — repas",
      "600006" => "Achats cuisine — buffets et apéros"
    }.freeze

    # Clé du réglage « Comptes de charge de la cuisine ». `Setting` ne stocke que
    # des chaînes : la liste d'identifiants s'y sérialise séparée par des virgules.
    EXPENSE_ACCOUNTS_KEY = "kitchen.expense_account_ids".freeze

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

    # Les comptes de charge sur lesquels s'imputent les dépenses de la cuisine.
    # C'est cette liste que lira le reporting de période (phase 2) : Michael
    # ajoute un compte depuis Paramètres > Cuisine, sans toucher au code.
    #
    # On relit les comptes en base à chaque appel plutôt que de faire confiance
    # aux identifiants stockés : un compte supprimé depuis disparaît de la liste
    # au lieu de faire planter la lecture. Aucun réglage = tableau vide, jamais
    # « tous les comptes » — un reporting qui invente son périmètre ment.
    def expense_accounts
      ids = expense_account_ids
      return [] if ids.empty?

      GeneralAccount.where(id: ids).ordered.to_a
    end

    def expense_account_ids
      Setting[EXPENSE_ACCOUNTS_KEY].to_s.split(",").filter_map { |id| Integer(id, exception: false) }
    end

    # Ce qui peut être coché dans le réglage : les charges actives du plan.
    def selectable_expense_accounts = GeneralAccount.actives.in_class(6).ordered

    # Types qui ne se proposent PLUS à la saisie (issue #238) : `trio` est
    # devenu le bouton « Trio » de la grille, qui coche les trois services du
    # jour, et `gouter` se coche dans la grille plutôt qu'il ne se choisit —
    # cocher son créneau avec le type « Repas » crée la ligne de goûter.
    UNPROPOSABLE_KINDS = %w[trio gouter].freeze

    # Types proposables aujourd'hui, dans l'ordre du catalogue.
    def enabled_kinds
      MealOrder::KINDS
        .reject { |kind| UNPROPOSABLE_KINDS.include?(kind) }
        .select { |kind| enabled?(MealOrder::KIND_FAMILIES[kind]) }
    end

    def setting_integer(key, fallback)
      raw = Setting[key]
      return fallback if raw.nil?

      Integer(raw, exception: false)
    end
  end
end
