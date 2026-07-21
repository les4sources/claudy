class StayDecorator < ApplicationDecorator
  delegate_all

  # Collection paginée (index Séjours) : préserve les méthodes will_paginate sur
  # la collection décorée — même pattern que CustomerDecorator.
  def self.collection_decorator_class
    PaginatingDecorator
  end

  # Statuts d'activité écartés de la composition « active » (miroir du scope
  # `ExperienceBooking.active`), filtrés EN MÉMOIRE pour éviter tout N+1.
  DEAD_EXPERIENCE_STATUSES = %w[cancelled refused].freeze

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

  # --- Composition complète du séjour (epic #66, Phase 5) ------------------
  # Bookables typés, pour la modale séjour (ouverte depuis le calendrier ou la
  # fiche client). On lit les `stay_items` préchargés (les soft-deleted sont
  # déjà exclus par le default_scope), regroupés par type d'occupation. Les
  # repas ne sont PAS des `stay_items` (pas d'occupation calendrier) : ils sont
  # rattachés en direct au séjour.

  def lodging_bookings
    bookables_of("Booking")
  end

  def space_bookings
    bookables_of("SpaceBooking")
  end

  def camping_bookings
    bookables_of("CampingBooking")
  end

  def van_bookings
    bookables_of("VanBooking")
  end

  def meals
    object.meal_orders.to_a
  end

  # Le séjour a-t-il au moins un élément de composition à afficher ?
  def any_composition?
    lodging_bookings.any? || space_bookings.any? || camping_bookings.any? ||
      van_bookings.any? || meals.any? || object.experience_bookings.active.any?
  end

  # Résumé compact de la composition pour l'index Séjours : « 1 gîte · 2 espaces
  # · 3 activités ». N'affiche que les catégories présentes. Tout est lu sur des
  # associations PRÉCHARGÉES (stay_items, experience_bookings, meal_orders) —
  # aucun accès base, contrairement à `stay_composition_summary` (helper de
  # fusion) qui interroge `experience_bookings.active` / `meal_orders`.
  def composition_summary
    parts = [
      compo_part(lodging_bookings.size, "gîte", "gîtes"),
      compo_part(space_bookings.size, "espace", "espaces"),
      compo_part(camping_bookings.size, "camping", "campings"),
      compo_part(van_bookings.size, "van", "vans"),
      compo_part(active_experiences_count, "activité", "activités"),
      compo_part(object.meal_orders.size, "repas", "repas")
    ].compact
    parts.any? ? parts.join(" · ") : "—"
  end

  # Notes INTERNES agrégées : celle du séjour + celles portées par les
  # bookables historiques (Booking/SpaceBooking, colonnes `notes`) — la plupart
  # des notes privées vivent encore là (399 bookings + 255 espaces au
  # 2026-07-21). Chaque entrée = { source:, text: } ; jamais exposé côté client.
  def internal_notes_entries
    entries = []
    entries << { source: "Séjour", text: object.notes } if object.notes.present?
    object.stay_items.each do |item|
      bookable = item.bookable
      note = bookable.try(:notes)
      next if note.blank? || note == object.notes

      label = item.bookable_type == "SpaceBooking" ? "Espaces" : "Hébergement"
      entries << { source: label, text: note }
    end
    entries.uniq { |e| e[:text] }
  end

  # Montant formaté d'un bookable (Booking/SpaceBooking/Camping/Van) ou d'un repas.
  def formatted_item_amount(record)
    money(record.try(:price_cents))
  end

  private

  # Bookables d'un type polymorphe donné, dans l'ordre des stay_items préchargés.
  def bookables_of(type)
    object.stay_items.select { |item| item.bookable_type == type }
          .map(&:bookable).compact
  end

  # Nombre d'activités actives, filtré EN MÉMOIRE (association préchargée) —
  # jamais `experience_bookings.active` (scope = requête).
  def active_experiences_count
    object.experience_bookings.reject { |eb| DEAD_EXPERIENCE_STATUSES.include?(eb.status) }.size
  end

  # Fragment « N mot » de la composition ; nil quand la catégorie est absente
  # (pour être filtré). Pluriel FR simple.
  def compo_part(count, singular, plural)
    return nil if count.to_i.zero?

    "#{count} #{count.to_i > 1 ? plural : singular}"
  end

  public

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
    lines = object.stay_items.map do |item|
      bookable = item.bookable
      next if bookable.nil?

      {
        kind: item.bookable_type,
        name: item_label(bookable),
        date_range: bookable_date_range(bookable),
        amount: h.humanized_money_with_symbol(Money.new(bookable.try(:price_cents).to_i))
      }
    end.compact

    # Repas (issue #79) : ce ne sont PAS des `stay_items` (has_many direct), mais
    # ils comptent dans le total — on les ajoute aux lignes pour que la
    # décomposition somme bien au total affiché (aucun écart lignes ≠ total).
    lines + object.meal_orders.map do |meal|
      {
        kind: "MealOrder",
        name: meal_line_label(meal),
        date_range: meal.date.present? ? h.l(meal.date, format: :long) : nil,
        amount: h.humanized_money_with_symbol(Money.new(meal.price_cents.to_i))
      }
    end
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

  # Badge discret de la catégorie de séjour (Michael 2026-07-21). nil → nil (rien
  # à afficher). Libellé FR via `Stay#category_label`.
  def category_badge
    label = object.category_label
    return if label.blank?
    h.content_tag(:span, label,
                  class: "inline-flex items-center rounded-full bg-indigo-50 px-2 py-0.5 text-xs font-medium text-indigo-700")
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
      # Un espace apparaît UNE fois par jour réservé dans l'association : on
      # agrège par nom avec le nombre de jours — « Grande Salle (3 j) » au lieu
      # de « Grande Salle, Grande Salle, Grande Salle » (aperçu de fusion).
      names = bookable.try(:spaces)&.map(&:name)&.compact_blank
      if names.present?
        names.tally.map { |name, days| days > 1 ? "#{name} (#{days} j)" : name }.join(", ")
      else
        h.t("public.stays.items.space")
      end
    when CampingBooking
      # Un CampingBooking terrasse (kind "terrasse") a son propre libellé (🪑),
      # distinct du camping (⛺) — décision Michael 2026-07-20.
      bookable.kind == "terrasse" ? h.t("public.stays.items.terrace") : h.t("public.stays.items.camping")
    when VanBooking
      h.t("public.stays.items.van")
    else
      h.t("public.stays.items.other")
    end
  end

  # Libellé d'une ligne repas (ex. « Repas — Buffet pain-fromages »).
  def meal_line_label(meal)
    "#{h.t('public.stays.items.meal')} — #{meal.label}"
  end

  # Plage de dates d'un bookable pour la page client. Utilise son décorateur
  # dédié quand il existe (Booking/SpaceBooking) ; à défaut (CampingBooking /
  # VanBooking, sans décorateur), dérive directement de from/to_date (issue #79).
  def bookable_date_range(bookable)
    bookable.decorate.try(:date_range)
  rescue Draper::UninferrableDecoratorError
    from = bookable.try(:from_date)
    to   = bookable.try(:to_date)
    return nil if from.blank? && to.blank?

    "#{from.present? ? h.l(from, format: :long) : '?'} → #{to.present? ? h.l(to, format: :long) : '?'}"
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
