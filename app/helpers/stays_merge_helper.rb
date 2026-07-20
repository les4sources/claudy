module StaysMergeHelper
  # --- Présélection intelligente du séjour survivant (epic #81) --------------
  # Ordre de préférence :
  #   1. un séjour qui PORTE DÉJÀ des paiements encaissés (ancre de paiement — on
  #      évite de déplacer l'historique comptable) ;
  #   2. à égalité, le séjour avec le PLUS D'OCCUPATIONS (composition la plus riche) ;
  #   3. puis le PLUS ANCIEN (plus petit id).
  # Renvoie `[stay, reason_key]` — la raison motive le badge « suggéré ».
  def suggested_merge_target(stays)
    return [nil, nil] if stays.blank?

    paying = stays.select { |s| s.amount_paid_cents.positive? }

    if paying.present?
      target = paying.max_by { |s| [s.stay_items.size, -s.id] }
      return [target, :payments]
    end

    max_items = stays.map { |s| s.stay_items.size }.max
    richest = stays.select { |s| s.stay_items.size == max_items }

    if richest.size == 1 && max_items.positive?
      [richest.first, :occupations]
    else
      [stays.min_by(&:id), :oldest]
    end
  end

  MERGE_SUGGESTION_REASONS = {
    payments:    "porte déjà des paiements",
    occupations: "composition la plus riche",
    oldest:      "le plus ancien"
  }.freeze

  def merge_suggestion_reason(key)
    MERGE_SUGGESTION_REASONS[key]
  end

  # Résumé compact de la composition d'un séjour : « 1 hébergement · 1 espace ·
  # 2 repas ». N'affiche que les catégories présentes.
  def stay_composition_summary(stay)
    decorator = stay.decorate
    parts = []
    parts << pluralize_fr(decorator.lodging_bookings.size, "hébergement")
    parts << pluralize_fr(decorator.space_bookings.size, "espace")
    parts << pluralize_fr(decorator.camping_bookings.size, "camping", plural: "campings")
    parts << pluralize_fr(decorator.van_bookings.size, "van")
    parts << pluralize_fr(stay.experience_bookings.active.size, "activité", plural: "activités")
    parts << pluralize_fr(stay.meal_orders.size, "repas", plural: "repas")
    present = parts.compact
    present.any? ? present.join(" · ") : "aucune composition"
  end

  # Résumé des paiements d'un séjour : « 2 paiements · 450 € encaissés » ou
  # « aucun paiement » — pour la carte de désignation de cible.
  def stay_payments_summary(stay)
    paid = stay.payments.paid
    count = paid.count
    return "aucun paiement encaissé" if count.zero?

    "#{pluralize_fr(count, 'paiement')} · #{humanized_money_with_symbol(Money.new(stay.amount_paid_cents))} encaissé#{'s' if count > 1}"
  end

  # Canal d'attribution d'un séjour, en libellé COURT pour la carte de fusion.
  # Distinct de `StaysHelper#stay_source_label` (libellés verbeux du form/index) :
  # ici la carte est une comparaison rapide, donc on abrège. Le nom de l'OTA
  # (Airbnb / Booking.com) est affiché à part par `platform_badge` (décorateur).
  MERGE_SOURCE_LABELS = {
    "reservation"  => "Funnel",
    "manual"       => "Manuel",
    "ota"          => "OTA",
    "tally_legacy" => "Import"
  }.freeze

  def merge_source_label(stay)
    MERGE_SOURCE_LABELS.fetch(stay.source, stay.source.to_s.humanize.presence || "—")
  end

  # Le séjour porte-t-il une note INTERNE quelque part ? (note du séjour lui-même
  # OU note d'un de ses bookables). Itère sur les `stay_items` PRÉCHARGÉS — pas de
  # requête supplémentaire (le contrôleur précharge `stay_items: :bookable`).
  def stay_has_internal_note?(stay)
    return true if stay.notes.present?

    stay.stay_items.any? { |item| item.bookable&.try(:notes).present? }
  end

  # Le séjour porte-t-il une note PUBLIQUE (ActionText) sur un de ses bookables ?
  # Seuls Booking et SpaceBooking exposent `public_notes` (has_rich_text) ; le
  # rich text est préchargé côté contrôleur (`preload_public_notes`) pour éviter
  # le N+1 sur cet accès.
  def stay_has_public_note?(stay)
    stay.stay_items.any? do |item|
      bookable = item.bookable
      bookable.respond_to?(:public_notes) && bookable.public_notes.body.present?
    end
  end

  # Libellé français d'une catégorie de composition (titre de section d'aperçu).
  MERGE_TYPE_LABELS = {
    lodging:  "Hébergements",
    space:    "Espaces",
    camping:  "Camping",
    van:      "Van",
    activity: "Activités",
    meal:     "Repas"
  }.freeze

  def merge_type_label(type)
    MERGE_TYPE_LABELS.fetch(type, type.to_s.humanize)
  end

  private

  # Pluralisation FR minimale (« 0 X » renvoie nil pour être filtré).
  def pluralize_fr(count, singular, plural: nil)
    return nil if count.to_i.zero?

    word = count.to_i > 1 ? (plural || "#{singular}s") : singular
    "#{count} #{word}"
  end
end
