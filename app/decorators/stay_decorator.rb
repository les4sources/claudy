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

  # `classes` : ancien badge texte, encore utilisé par d'autres vues.
  # `icon_classes` : teinte de marque, sans pastille de fond — le logo se suffit
  # à lui-même. `fill-current` est INDISPENSABLE : les `<path>` des partials
  # partagés ne portent aucun attribut `fill` et retombent donc sur le noir par
  # défaut. `fill` étant une propriété héritée, la poser sur le `<span>` la fait
  # descendre jusqu'au `<path>` — sans toucher aux partials, que `BookingDecorator`
  # utilise aussi.
  PLATFORM_STYLES = {
    "airbnb"        => { label: "Airbnb", classes: "bg-rose-50 text-rose-600 ring-1 ring-rose-100",
                         icon_classes: "fill-current text-rose-500" },
    "bookingdotcom" => { label: "Booking.com", classes: "bg-blue-50 text-blue-700 ring-1 ring-blue-100",
                         icon_classes: "fill-current text-blue-700" }
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

  # Locations de hamacs (issue #138) — une entrée par plage de nuits et par type.
  def hamac_bookings
    bookables_of("HamacBooking")
  end

  def meals
    object.meal_orders.to_a
  end

  # Le séjour a-t-il au moins un élément de composition à afficher ?
  def any_composition?
    lodging_bookings.any? || space_bookings.any? || camping_bookings.any? ||
      van_bookings.any? || hamac_bookings.any? || meals.any? ||
      object.experience_bookings.active.any?
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
      compo_part(hamac_bookings.sum { |h| h.count.to_i }, "hamac", "hamacs"),
      compo_part(active_experiences_count, "activité", "activités"),
      compo_part(object.meal_orders.size, "repas", "repas")
    ].compact
    parts.any? ? parts.join(" · ") : "—"
  end

  # --- Contact d'origine porté par les réservables (Michael 2026-07-26) -----
  #
  # Tout l'historique importé est rattaché au client FOURRE-TOUT
  # (`client@les4sources.be`, ou son équivalent par OTA) faute d'email
  # exploitable à la migration. Le seul nom réel du dossier vit alors sur le
  # RÉSERVABLE, dans ses colonnes `firstname` / `lastname` / `group_name` —
  # exactement comme les notes privées (cf. `internal_notes_entries`).
  #
  # Sans ce rappel, la fiche d'édition d'un séjour legacy n'affiche AUCUN nom :
  # elle montre « Client Les 4 Sources » et l'info existante reste invisible.
  # Même logique que `internal_notes_entries` : on lit les `stay_items`
  # préchargés, aucun accès base supplémentaire.

  # Le séjour est-il rattaché à un client fourre-tout (générique ou par OTA) ?
  def catch_all_customer?
    Customer::CATCH_ALL_EMAILS.include?(object.customer&.email)
  end

  # Nom À AFFICHER pour le séjour (Michael 2026-07-26). Sur un séjour rattaché au
  # client FOURRE-TOUT, « Client Les 4 Sources » ne dit rien : on lui préfère le
  # `group_name` porté par la réservation d'origine (« Camp louveteaux »), qui est
  # le nom sous lequel l'équipe connaît le dossier.
  #
  # On regarde AUSSI les bookables soft-deleted : sur 620 séjours fourre-tout,
  # 77 n'ont plus de réservable vivant et leur nom ne vit QUE là (c'est le cas du
  # séjour 1417 qui a motivé ce changement). Le repli reste le nom du client.
  #
  # COÛT : la relecture unscoped n'a lieu que si le client est un fourre-tout ET
  # que les bookables préchargés n'ont rien donné — jamais sur un séjour normal.
  def display_name
    return object.customer&.name unless catch_all_customer?

    origin_group_name.presence || object.customer&.name
  end

  def origin_group_name
    @origin_group_name ||= begin
      vivant = object.stay_items.filter_map { |i| i.bookable.try(:group_name).presence }.first
      vivant || supprime_group_name
    end
  end

  # Une entrée par réservable porteur d'un contact, dédoublonnée. Un réservable
  # sans aucune coordonnée est ignoré (rien à rappeler).
  def origin_contacts
    object.stay_items.filter_map { |item| origin_contact_for(item) }
          .uniq { |e| [e[:name], e[:group], e[:email], e[:phone]] }
  end

  # Le contact du réservable APPORTE-T-IL quelque chose que le client ne dit pas
  # déjà ? Vrai dès que le séjour est sur un fourre-tout (le client ne nomme
  # personne) ou qu'un nom/groupe diffère du nom du client.
  def origin_contacts_worth_showing?
    return false if origin_contacts.empty?
    return true if catch_all_customer?

    customer_name = object.customer&.name.to_s.strip.downcase
    origin_contacts.any? do |c|
      c[:group].present? || (c[:name].present? && c[:name].strip.downcase != customer_name)
    end
  end

  private

  # Dernier recours : le réservable a été soft-deleted, son nom de groupe n'est
  # plus atteignable par l'association (le default_scope l'exclut).
  def supprime_group_name
    object.stay_items.each do |item|
      next if item.bookable.present?

      record = item.bookable_type.constantize.unscoped.find_by(id: item.bookable_id)
      name = record.try(:group_name).presence
      return name if name
    end
    nil
  end

  def origin_contact_for(item)
    bookable = item.bookable
    return nil if bookable.nil?

    name  = [bookable.try(:firstname), bookable.try(:lastname)].compact_blank.join(" ").presence
    group = bookable.try(:group_name).presence
    email = bookable.try(:email).presence
    phone = bookable.try(:phone).presence
    return nil if name.blank? && group.blank? && email.blank? && phone.blank?

    { label:     item.bookable_type == "SpaceBooking" ? "Espaces" : "Hébergement",
      reference: "#{item.bookable_type.underscore.humanize} ##{item.bookable_id}",
      name: name, group: group, email: email, phone: phone }
  end

  public

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
  #
  # ICÔNE et non libellé (Michael 2026-07-26) : on réutilise les partials SVG
  # déjà en place (`shared/_airbnb_icon`, `shared/_bookingdotcom_icon`), ceux-là
  # mêmes qu'utilisait `BookingDecorator`. Le logo se reconnaît d'un coup d'œil
  # là où « Airbnb » en toutes lettres consommait de la largeur sur chaque ligne.
  # Le nom reste porté par `title` + `aria-label` : l'information n'est pas
  # perdue pour un lecteur d'écran ni au survol.
  PLATFORM_ICON_PARTIALS = {
    "airbnb"        => "shared/airbnb_icon",
    "bookingdotcom" => "shared/bookingdotcom_icon"
  }.freeze

  def platform_badge
    platform = primary_bookable&.try(:platform)
    partial  = PLATFORM_ICON_PARTIALS[platform]
    return if partial.nil?

    style = PLATFORM_STYLES[platform]
    h.content_tag(:span, h.render(partial),
                  class: "inline-flex items-center #{style[:icon_classes]}",
                  title: "Réservation provenant de #{style[:label]}",
                  role: "img", aria: { label: style[:label] })
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
    when HamacBooking
      "#{h.t('public.stays.items.hamac')} — #{bookable.label} × #{bookable.count}"
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
