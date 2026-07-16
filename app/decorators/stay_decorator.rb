class StayDecorator < ApplicationDecorator
  delegate_all

  STATUS_STYLES = {
    "confirmed" => { label: "Confirmé", classes: "bg-green-100 text-green-800" },
    "pending"   => { label: "En attente", classes: "bg-amber-100 text-amber-800" },
    "canceled"  => { label: "Annulé", classes: "bg-red-100 text-red-800" },
    "cancelled" => { label: "Annulé", classes: "bg-red-100 text-red-800" }
  }.freeze

  PLATFORM_STYLES = {
    "airbnb"        => { label: "Airbnb", classes: "bg-rose-50 text-rose-600 ring-1 ring-rose-100" },
    "bookingdotcom" => { label: "Booking.com", classes: "bg-blue-50 text-blue-700 ring-1 ring-blue-100" }
  }.freeze

  # Premier objet réservable du séjour (Booking / SpaceBooking) — porte le contact.
  def primary_bookable
    @primary_bookable ||= object.stay_items.first&.bookable
  end

  # Badge plateforme (Airbnb / Booking.com) si le séjour provient d'une OTA.
  # nil pour les réservations directes / web. Lit `platform` du bookable
  # (uniforme pour Booking et SpaceBooking).
  def platform_badge
    style = PLATFORM_STYLES[primary_bookable&.try(:platform)]
    return if style.nil?
    h.content_tag(:span, style[:label],
                  class: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium #{style[:classes]}",
                  title: "Réservation provenant de #{style[:label]}")
  end

  PAYMENT_STATUS_STYLES = {
    "paid"           => { key: "paid", classes: "bg-green-100 text-green-800" },
    "partially_paid" => { key: "partially_paid", classes: "bg-amber-100 text-amber-800" },
    "pending"        => { key: "pending", classes: "bg-gray-100 text-gray-700" }
  }.freeze

  # Badge du statut de paiement du séjour (epic #26). Libellé traduit — la page
  # client est destinée à devenir trilingue (issue #15).
  def payment_status_badge
    style = PAYMENT_STATUS_STYLES.fetch(object.payment_status, PAYMENT_STATUS_STYLES["pending"])
    h.content_tag(:span, h.t("public.stays.payment_status.#{style[:key]}"),
                  class: "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium #{style[:classes]}")
  end

  # Lignes du séjour-composite : un réservable (Booking / SpaceBooking) par ligne,
  # avec ses dates et son montant. Alimente la page client /sejour/:token.
  def item_lines
    object.stay_items.map do |item|
      bookable = item.bookable
      next if bookable.nil?

      {
        kind: item.bookable_type,
        name: item_label(bookable),
        date_range: bookable.decorate.try(:date_range),
        amount: h.humanized_money_with_symbol(Money.new(bookable.try(:price_cents).to_i))
      }
    end.compact
  end

  # Total formaté pour la page client. Volontairement PAS nommé `total_amount` :
  # les vues admin appellent `@stay.total_amount.format` et attendent un Money.
  def formatted_total
    h.humanized_money_with_symbol(object.total_amount)
  end

  def status_badge
    style = STATUS_STYLES.fetch(object.status, { label: object.status.presence || "—", classes: "bg-gray-100 text-gray-700" })
    h.content_tag(:span, style[:label],
                  class: "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium #{style[:classes]}")
  end

  # Plage de dates au format français long (ex. « 12 février 2026 »).
  def date_range
    return "—" if arrival_date.blank? && departure_date.blank?
    from = arrival_date.present? ? h.l(arrival_date, format: :long) : "?"
    to = departure_date.present? ? h.l(departure_date, format: :long) : "?"
    "#{from} → #{to}"
  end

  # Libellé d'une ligne du séjour : ce qui est réservé (hébergement, espace), pas
  # qui l'a réservé — le nom du client est déjà affiché en tête de page.
  def item_label(bookable)
    case bookable
    when Booking
      bookable.lodging&.name.presence || h.t("public.stays.items.lodging")
    when SpaceBooking
      spaces = bookable.try(:spaces)&.map(&:name)&.compact_blank
      spaces.presence&.join(", ") || h.t("public.stays.items.space")
    else
      h.t("public.stays.items.other")
    end
  end

  # Nom/prénom + nom de groupe issus du booking sous-jacent.
  def contact_line
    return "—" if primary_bookable.nil?
    person = [primary_bookable.try(:firstname), primary_bookable.try(:lastname)].compact_blank.join(" ")
    group = primary_bookable.try(:group_name).presence
    [person.presence, group].compact.join(" · ").presence || "—"
  end

  # --- Ventilation du montant exigible (epic #55, Phase 3) ---------------
  # Montants formatés en euros pour la page client. On lit l'arithmétique du
  # modèle (source unique de vérité « total prévu vs exigible »).

  def formatted_amount_paid
    money(object.amount_paid_cents)
  end

  def formatted_lodging_and_spaces
    money(object.lodging_and_spaces_amount_cents)
  end

  def formatted_experiences_confirmed
    money(object.experiences_confirmed_amount_cents)
  end

  def formatted_experiences_pending
    money(object.experiences_pending_amount_cents)
  end

  def formatted_balance_due
    money(object.balance_due_cents)
  end

  def has_confirmed_experiences?
    object.experiences_confirmed_amount_cents.positive?
  end

  def has_pending_experiences?
    object.experiences_pending_amount_cents.positive?
  end

  # Faut-il afficher le bloc de ventilation du solde ? Dès qu'il y a quelque
  # chose à dire : un exigible à régler, un encaissé à créditer, ou des
  # activités en attente à signaler.
  def show_balance_section?
    object.payable_now? ||
      object.amount_paid_cents.positive? ||
      has_pending_experiences?
  end

  # Bouton « Payer le solde » : un exigible strictement positif ET aucun
  # paiement `pending` déjà en cours (l'acompte non réglé, par exemple, est déjà
  # couvert par son propre CTA — on n'empile pas deux boutons pour la même dette).
  def show_balance_cta?
    object.payable_now? && object.payments.pending.none?
  end

  private

  def money(cents)
    h.humanized_money_with_symbol(Money.new(cents.to_i))
  end
end
