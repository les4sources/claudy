module KitchenHelper
  # Libellé d'un séjour dans le sélecteur : le client d'abord, les dates ensuite.
  # C'est par le nom que Malau cherche.
  def stay_choice_label(stay)
    name  = stay.customer&.name.presence || "Séjour ##{stay.id}"
    return name if stay.arrival_date.blank?

    "#{name} — du #{l(stay.arrival_date, format: '%-d/%m')} au #{stay.departure_date ? l(stay.departure_date, format: '%-d/%m') : '?'}"
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

    user = User.find_by(id: whodunnit)
    return whodunnit.to_s if user.nil?

    user.human&.name.presence || user.email
  end

  def kitchen_history_value(field, value)
    return "—" if value.blank?

    case field
    when "kind"                 then MealOrder.label_for(value)
    when "moment"               then MealOrder::MOMENT_LABELS[value.to_s]
    when "status"               then MealOrder::STATUS_LABELS[value.to_s]
    when "validation"           then MealOrder::VALIDATION_LABELS[value.to_s]
    when "responsible_human_id" then Human.find_by(id: value)&.name || "##{value}"
    when "unit_price_cents"     then humanized_money_with_symbol(Money.new(value.to_i))
    when "date"                 then l(value.to_date, format: :long)
    else value.to_s
    end
  end
end
