module KitchenHelper
  # Libellé d'un séjour dans le sélecteur : le client d'abord, les dates ensuite.
  # C'est par le nom que Malau cherche.
  def stay_choice_label(stay)
    name  = stay.customer&.name.presence || "Séjour ##{stay.id}"
    return name if stay.arrival_date.blank?

    "#{name} — du #{l(stay.arrival_date, format: '%-d/%m')} au #{stay.departure_date ? l(stay.departure_date, format: '%-d/%m') : '?'}"
  end

  # Table type → tarif du barème, en euros, pour l'aide vivante sous le champ
  # « Prix par personne ». Un type sans tarif catalogué n'y figure pas : l'aide
  # retombe alors sur sa phrase générique.
  def meal_rates_json
    MealOrder::KINDS.filter_map { |kind|
      cents = Pricing::Catalog.meal_per_person_cents(kind)
      [kind, (cents / 100.0)] if cents
    }.to_h.to_json
  end

  # La même table, mais en CENTS : la grille (issue #238) calcule un total, pas
  # une phrase d'aide, et un total se compte en cents pour ne pas dériver.
  def meal_rates_cents_json
    MealOrder::KINDS.filter_map { |kind|
      cents = Pricing::Catalog.meal_per_person_cents(kind)
      [kind, cents] if cents
    }.to_h.to_json
  end

  # LE statut affiché (2026-10-19), même couleur dans les deux vues : ambre =
  # la cuisine doit répondre, indigo = le client se renseigne, vert = prévu,
  # rouge = à couvrir. Les teintes diffèrent aussi en clarté, pas seulement en
  # couleur.
  BOARD_STATUS_STYLES = {
    "to_validate" => "bg-amber-100 text-amber-900",
    "inquiry"     => "bg-indigo-100 text-indigo-900",
    "planned"     => "bg-emerald-100 text-emerald-900",
    "to_cover"    => "bg-red-100 text-red-900"
  }.freeze

  # La phrase sous le titre de chaque section : ce qu'on attend de qui
  # regarde, dans SA vue.
  BOARD_SECTION_HINTS = {
    kitchen: {
      "to_validate" => "Le client attend la réponse de la cuisine : est-ce possible ?",
      "planned"     => "Le planning : cuisine et client d'accord, on cuisine.",
      "inquiry"     => "La cuisine a dit oui, le client n'a pas encore décidé. Rien à préparer.",
      "to_cover"    => "La cuisine a dit non. L'accueil s'en occupe, rien à faire ici."
    },
    reception: {
      "to_cover"    => "La cuisine a dit non : confier à quelqu'un d'autre, ou prévenir le client.",
      "inquiry"     => "La cuisine est d'accord. Relancer le client : le veut-il vraiment ?",
      "to_validate" => "En attente de la cuisine. La date de demande passe en ambre après 14 jours.",
      "planned"     => "Tout le monde est d'accord. Compté dans le prix du séjour."
    }
  }.freeze

  # Les colonnes d'une section, selon la vue : chaque métier ne voit que ce
  # qui l'aide à agir sur CETTE section.
  BOARD_COLUMNS = {
    kitchen: {
      "to_validate" => %i[date client kind people responsible requested_at actions],
      "planned"     => %i[moment client kind people responsible client_status actions],
      "inquiry"     => %i[date client kind people responsible actions],
      "to_cover"    => %i[date client kind people reason actions]
    },
    reception: {
      "to_cover"    => %i[date client kind people reason actions],
      "inquiry"     => %i[requested_at date client kind people price actions],
      "to_validate" => %i[requested_at date client kind people waiting_for actions],
      "planned"     => %i[date client kind people responsible price client_status actions]
    }
  }.freeze
  ARCHIVE_COLUMNS = %i[date client kind people responsible client_status reason actions].freeze

  BOARD_COLUMN_TITLES = {
    date: "Date", moment: "Moment", client: "Client", kind: "Prestation", people: "Convives",
    responsible: "Qui s'en charge", requested_at: "Demandée le", client_status: "Côté client",
    reason: "Motif", price: "Prix", waiting_for: "Attend", actions: ""
  }.freeze

  def board_status_badge(status, text = MealOrder::BOARD_STATUS_LABELS[status])
    content_tag(:span, text,
                class: "inline-flex items-center rounded-full px-3 py-1 text-sm font-semibold " \
                       "#{BOARD_STATUS_STYLES.fetch(status.to_s, 'bg-gray-100 text-gray-700')}")
  end

  def board_section_hint(view, status) = BOARD_SECTION_HINTS.dig(view, status)

  def board_columns(view, status)
    BOARD_COLUMNS.dig(view, status) || ARCHIVE_COLUMNS
  end

  # À la création, on ne propose que les deux états d'entrée : le client se
  # renseigne, ou il demande fermement. Confirmer et annuler viennent après.
  def status_choices(order)
    statuses = order.persisted? ? MealOrder::STATUSES : %w[inquiry requested]
    statuses.map { |status| [MealOrder::STATUS_LABELS[status], status] }
  end

  # Champs dont le changement mérite d'être lu dans l'historique. Le reste
  # (horodatages, prix recalculé) est du bruit pour qui cherche « qui a changé
  # le nombre de convives, et quand ».
  HISTORY_FIELDS = {
    "kind"                 => "Type",
    "date"                 => "Date",
    "moment"               => "Moment",
    "people"               => "Convives",
    "status"               => "Statut client",
    "validation"           => "Validation cuisine",
    "responsible_human_id" => "S'en charge",
    "unit_price_cents"     => "Prix par personne"
  }.freeze

  def kitchen_history_entries(order)
    # Une commande éditée trente fois, c'est trente requêtes `User.find_by` et
    # autant de `Human.find_by` si on les résout ligne à ligne. On mémoïse le
    # temps du rendu.
    @kitchen_history_users  = {}
    @kitchen_history_humans = {}

    order.versions.reorder(created_at: :desc, id: :desc).filter_map do |version|
      changes = (version.changeset || {}).slice(*HISTORY_FIELDS.keys)
      next if changes.empty? && version.event != "create"

      { at: version.created_at,
        author: kitchen_history_author(version.whodunnit),
        event: version.event,
        changes: changes.map { |field, (before, after)|
          { label: HISTORY_FIELDS[field],
            before: kitchen_history_value(field, before),
            after: kitchen_history_value(field, after) }
        } }
    end
  end

  # `whodunnit` porte l'id du compte connecté. On rend un nom lisible : le
  # membre rattaché au compte quand il y en a un, sinon son email.
  def kitchen_history_author(whodunnit)
    return "—" if whodunnit.blank?

    user = (@kitchen_history_users ||= {}).fetch(whodunnit.to_s) { |key| @kitchen_history_users[key] = User.find_by(id: key) }
    return whodunnit.to_s if user.nil?

    user.human&.name.presence || user.email
  end

  def kitchen_history_human(id)
    (@kitchen_history_humans ||= {}).fetch(id.to_s) { |key| @kitchen_history_humans[key] = Human.find_by(id: key) }
  end

  def kitchen_history_value(field, value)
    return "—" if value.blank?

    case field
    when "kind"                 then MealOrder.label_for(value)
    when "moment"               then MealOrder::MOMENT_LABELS[value.to_s]
    when "status"               then MealOrder::STATUS_LABELS[value.to_s]
    when "validation"           then MealOrder::VALIDATION_LABELS[value.to_s]
    when "responsible_human_id" then kitchen_history_human(value)&.name || "##{value}"
    when "unit_price_cents"     then humanized_money_with_symbol(Money.new(value.to_i))
    when "date"                 then l(value.to_date, format: :long)
    else value.to_s
    end
  end
end
