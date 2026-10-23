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

  # `pre_confirmed` (issue #215) : le Pôle Accueil a validé la demande et attend
  # l'acompte. Teinte INDIGO — délibérément distincte de l'ambre de `pending` et
  # du vert de `confirmed` : au coup d'œil sur l'index, on doit voir la
  # différence entre « personne n'a encore regardé » et « on attend l'argent ».
  STATUS_STYLES = {
    "confirmed"     => { label: "Confirmé", classes: "bg-green-100 text-green-800" },
    "pre_confirmed" => { label: "Pré-confirmé", classes: "bg-indigo-100 text-indigo-800" },
    "pending"       => { label: "En attente", classes: "bg-amber-100 text-amber-800" },
    "canceled"      => { label: "Annulé", classes: "bg-red-100 text-red-800" },
    "cancelled"     => { label: "Annulé", classes: "bg-red-100 text-red-800" }
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
    object.meal_orders.active.to_a
  end

  # Draps (epic #260, phase 2) — une ligne par type de lit, simple avant double.
  def linen_orders
    object.linen_orders.ordered.to_a
  end

  # Le séjour a-t-il au moins un élément de composition à afficher ?
  def any_composition?
    lodging_bookings.any? || space_bookings.any? || camping_bookings.any? ||
      van_bookings.any? || hamac_bookings.any? || linen_orders.any? || meals.any? ||
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
      compo_part(linen_orders.sum { |l| l.quantity.to_i }, "jeu de draps", "jeux de draps"),
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

    origin_label.presence || object.customer&.name
  end

  # Adresse email à laquelle ÉCRIRE AU CLIENT, quand on en a une (Michael
  # 2026-08-29). Affichée sous le nom dans la modale séjour, en lien `mailto:`.
  #
  # Sur un séjour FOURRE-TOUT, `customer.email` est une boîte MAISON
  # (`client@les4sources.be` ou son équivalent OTA) : la proposer en mailto
  # écrirait aux 4 Sources elles-mêmes. On lui préfère alors l'adresse portée par
  # la réservation d'origine — la seule qui joigne vraiment la personne. nil
  # quand il n'y a rien à écrire : mieux vaut aucun lien qu'un lien trompeur.
  def contact_email
    return object.customer&.email.presence unless catch_all_customer?

    origin_contacts.filter_map { |contact| contact[:email] }.first
  end

  # Le client de ce séjour n'a-t-il AUCUNE adresse email (issue #232) ? Vrai
  # seulement pour un vrai client sans email — un séjour fourre-tout est un cas
  # distinct, déjà signalé par son propre bloc « Contact d'origine », et son
  # client porte bel et bien une adresse (une boîte maison).
  def no_contact_email?
    return false if catch_all_customer?

    object.customer.present? && object.customer.email.blank?
  end

  # Nom porté par la réservation d'origine : le NOM DE GROUPE d'abord, à défaut
  # le nom de la personne (`firstname` / `lastname`). Les résas OTA n'ont pas de
  # nom de groupe mais bien un prénom — le séjour 1440 (Airbnb) affiche « Freya »
  # au calendrier via `group_or_name`, et doit le faire ici aussi.
  def origin_label
    @origin_label ||= begin
      vivants = object.stay_items.filter_map { |i| bookable_label(i.bookable) }
      vivants.first || label_depuis_supprime
    end
  end

  # Même ordre de préférence que `BookingDecorator#group_or_name`, dont le
  # calendrier se sert : groupe, puis personne.
  def bookable_label(bookable)
    return nil if bookable.nil?

    bookable.try(:group_name).presence ||
      [bookable.try(:firstname), bookable.try(:lastname)].compact_blank.join(" ").presence
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

  # Dernier recours : le réservable a été soft-deleted, son nom n'est plus
  # atteignable par l'association (le default_scope l'exclut).
  def label_depuis_supprime
    object.stay_items.each do |item|
      next if item.bookable.present?

      record = item.bookable_type.constantize.unscoped.find_by(id: item.bookable_id)
      label = bookable_label(record)
      return label if label
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
    stay_note = object.internal_note_text
    entries = []
    entries << { source: "Séjour", text: stay_note } if stay_note.present?
    object.stay_items.each do |item|
      bookable = item.bookable
      note = bookable.try(:notes)
      next if note.blank? || note == stay_note

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
  #
  # RIEN À PAYER = AUCUN BADGE (Michael 2026-08-24). Un séjour à 0 € reste
  # `pending` par construction (`Stay#set_payment_status` refuse de basculer en
  # « payé » sans encaissement) : afficher « En attente de paiement » sur une
  # ligne à 0 € annonce une dette qui n'existe pas. On lit `payment_status` et
  # non `amount_paid_cents` — colonne contre requête : la fiche client liste
  # jusqu'à plusieurs centaines de séjours, un N+1 y coûterait cher. Dès qu'un
  # euro est encaissé le statut n'est plus `pending`, donc le badge revient.
  def payment_status_badge
    return if object.total_amount_cents.to_i.zero? && object.payment_status == "pending"

    style = PAYMENT_STATUS_STYLES.fetch(object.payment_status, PAYMENT_STATUS_STYLES["pending"])
    h.content_tag(:span, h.t("public.stays.payment_status.#{style[:key]}"),
                  class: "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium #{style[:classes]}")
  end

  # --- Pré-confirmation (issue #215) -------------------------------------
  # Le bouton n'a de sens que sur une demande ENCORE EN ATTENTE, rattachée à un
  # client réel et joignable. Sur un séjour déjà `pre_confirmed`, l'acompte est
  # posé : le proposer à nouveau créerait un second Payment (le service refuse
  # de toute façon, mais un bouton qui ne peut qu'échouer n'a rien à faire là).
  def can_pre_confirm?
    object.status == "pending" &&
      object.customer&.email.present? &&
      !object.customer.catch_all?
  end

  # --- Refus d'une demande (Michael 2026-09-08) ---------------------------
  # Le pendant du bouton ci-dessus. Visible sur une demande EN ATTENTE comme sur
  # une demande PRÉ-CONFIRMÉE : tant que l'acompte n'est pas payé, rien n'est
  # acquis — et c'est justement là que le refus est le plus utile, puisque le
  # séjour bloque désormais des dates qu'il faut rendre.
  #
  # Contrairement à `can_pre_confirm?`, on n'exige PAS un client joignable : le
  # dossier doit pouvoir se fermer même sans adresse. C'est l'écran de refus qui
  # prévient qu'aucun email ne partira.
  def can_refuse?
    Stays::Refuser::REFUSABLE_STATUSES.include?(object.status.to_s) &&
      object.deleted_at.blank?
  end

  # --- Email de confirmation (Malau, 2026-08-20) -------------------------
  # L'envoi nominal est automatique à la bascule vers `confirmed` ; ces trois
  # méthodes n'habillent que le RENVOI manuel depuis la fiche admin.

  # Le bouton n'a de sens que sur un séjour confirmé, rattaché à un client réel
  # (un fourre-tout n'a pas d'adresse de client) et pourvu d'un email.
  def can_resend_confirmation_email?
    object.status == "confirmed" &&
      object.customer&.email.present? &&
      !object.customer.catch_all?
  end

  # Confirmer un séjour DÉJÀ PASSÉ (Michael, 2026-10-13) : par défaut aucun email
  # ne part (`Stays::ConfirmationNotifier` s'arrête au départ), mais l'équipe
  # peut vouloir prévenir le client. Le bouton ouvre alors une modale qui pose
  # la question — seulement si un email POURRAIT partir.
  def ask_email_on_confirm?
    !object.canceled? && object.status != "confirmed" &&
      object.departure_date.present? && object.departure_date < Date.current &&
      object.customer&.email.present? && !object.customer.catch_all?
  end

  # Le libellé porte l'information : « envoyer » quand rien n'est parti,
  # « renvoyer » quand un email existe déjà. Sans cette distinction, personne ne
  # sait si cliquer va doubler un message que le client a déjà reçu.
  def confirmation_email_button_label
    object.confirmation_email_sent_at.present? ? "Renvoyer l'email ✉" : "Envoyer l'email ✉"
  end

  # Infobulle : la date d'envoi précise, ou l'absence d'envoi.
  def confirmation_email_hint
    sent_at = object.confirmation_email_sent_at
    return "Aucun email de confirmation n'a encore été envoyé pour ce séjour." if sent_at.blank?

    "Email de confirmation envoyé le #{h.l(sent_at, format: :long)}."
  end

  # Lignes du séjour-composite : un réservable (Booking / SpaceBooking) par ligne,
  # avec ses dates et son montant. Alimente la page client /sejour/:token.
  #
  # Prix imposé (Michael, 2026-10-19) : il remplace le prix calculé de tout ce
  # qui compose le séjour, bar excepté (`Stay#recompute_aggregates!`). Le client
  # du Grand-Duc lisait « 2 000 € » sur sa ligne puis « Total 1 850 € », sans
  # rien pour relier les deux. Les lignes montrent donc le prix demandé, jamais
  # le prix calculé — cf. `price_override_placement`.
  def item_lines
    lines = composition_lines
    case price_override_placement
    when :item
      lines = [lines.first.merge(amount: formatted_price_override)]
    when :agreed_line
      lines = lines.map { |line| line.merge(amount: nil) } + [agreed_price_line]
    end

    lines += service_lines_for_display
    bar = bar_line
    bar ? lines + [bar] : lines
  end

  # Où le prix imposé s'affiche, quand il y en a un :
  #   :item / :activity — une seule ligne le porte : elle prend le prix demandé ;
  #   :agreed_line      — plusieurs lignes : aucune ne garde de montant (le prix
  #                       imposé ne se ventile pas), une ligne « Prix convenu »
  #                       porte le tout.
  # nil sans prix imposé : chaque ligne garde son prix calculé.
  def price_override_placement
    return nil unless object.price_overridden?

    covered = composition_lines.size + raw_activity_lines.size
    return :agreed_line unless covered == 1

    composition_lines.any? ? :item : :activity
  end

  def composition_lines
    @composition_lines ||= build_composition_lines
  end

  def build_composition_lines
    lines = object.stay_items.map do |item|
      bookable = item.bookable
      next if bookable.nil?

      {
        kind: item.bookable_type,
        icon: line_icon(item.bookable_type, bookable),
        name: item_label(bookable),
        date_range: bookable_date_range(bookable),
        amount: h.humanized_money_with_symbol(Money.new(bookable.try(:price_cents).to_i))
      }
    end.compact

    # Repas (issue #79) : ce ne sont PAS des `stay_items` (has_many direct), mais
    # ils comptent dans le total — on les ajoute aux lignes pour que la
    # décomposition somme bien au total affiché (aucun écart lignes ≠ total).
    lines += object.meal_orders.billable.map do |meal|
      {
        kind: "MealOrder",
        icon: :utensils,
        name: meal_line_label(meal),
        date_range: meal.date.present? ? h.l(meal.date, format: :long) : nil,
        amount: h.humanized_money_with_symbol(Money.new(meal.price_cents.to_i))
      }
    end

    # Draps (epic #260, phase 2) : pas davantage des `stay_items` que les repas,
    # et ils comptent dans le total — sans eux, les lignes de la page client ne
    # sommeraient plus au total affiché.
    lines += object.linen_orders.ordered.map do |linen|
      {
        kind: "LinenOrder",
        icon: :bed,
        name: "#{linen.label} × #{linen.quantity}",
        date_range: nil,
        amount: h.humanized_money_with_symbol(Money.new(linen.price_cents.to_i))
      }
    end

    # Pizza Party rattachée (Michael, 2026-10-19) : elle compte dans le total
    # (`Stay#recompute_aggregates!`), la page doit donc la montrer. Sans elle,
    # le client du séjour #1518 lisait un total de 1 980 € sans pouvoir
    # retrouver les 140 € de sa party. Remboursée ou annulée : hors du total,
    # hors de la page.
    lines += object.party_reservations.active.ordered.map do |party|
      when_parts = [party.held_on.present? ? h.l(party.held_on, format: :long) : nil, party.slot.presence].compact
      {
        kind: "PartyReservation",
        icon: :flame,
        name: party.persons.to_i.positive? ? "Pizza Party · #{party.persons} pers." : "Pizza Party",
        date_range: when_parts.join(" · ").presence,
        amount: h.humanized_money_with_symbol(party.price)
      }
    end

    lines
  end

  # Bar (Michael, 2026-10-13) : une seule ligne pour toute la feuille. Le
  # détail article par article reste à l'équipe ; le client y lit ce qui
  # s'ajoute à son total. Hors prix imposé : elle garde toujours son montant.
  def bar_line
    bar_cents = object.bar_amount_cents
    return nil unless bar_cents.positive?

    {
      kind: "BarConsumption",
      icon: :utensils,
      name: "Consommations au bar",
      date_range: nil,
      amount: h.humanized_money_with_symbol(Money.new(bar_cents))
    }
  end

  # Services annexes (Michael, 2026-10-23) : une ligne chacun, avec son
  # montant, prix imposé ou non — comme le bar, ils s'ajoutent au prix convenu.
  def service_lines_for_display
    object.service_lines.ordered.map do |line|
      {
        kind: "StayServiceLine",
        icon: :sparkles,
        name: line.label,
        date_range: nil,
        amount: h.humanized_money_with_symbol(line.amount)
      }
    end
  end

  def agreed_price_line
    {
      kind: "PriceOverride",
      icon: :check,
      name: h.t("public.stays.items.agreed_price"),
      date_range: nil,
      amount: formatted_price_override
    }
  end

  def formatted_price_override
    h.humanized_money_with_symbol(Money.new(object.price_override_cents.to_i))
  end

  # Brouette de bûches incluse (epic #260, décision 6) : information portée par
  # les gîtes qui ont un poêle. Vide quand le séjour n'en occupe aucun.
  def firewood_lodging_names
    lodging_bookings.filter_map { |b| b.lodging&.name }
                    .uniq
                    .select { |name| Pricing::Catalog.firewood_included?(name) }
  end

  def firewood_included?
    firewood_lodging_names.any?
  end

  # Activités du séjour, pour la page client (Michael, 2026-08-20). Elles ne sont
  # NI des `stay_items` (aucune occupation d'hébergement) NI des repas : la page
  # publique n'en montrait donc que le MONTANT, dans la ventilation du solde —
  # jamais lesquelles. Un client qui a réservé une balade avec les ânes doit lire
  # « balade avec les ânes », pas « activités validées : 30 € ».
  #
  # Les `pending` sont affichées mais marquées « à confirmer » : elles ne sont
  # pas exigibles (cf. `Stay#payable_amount_cents`), et la page ne doit pas
  # laisser croire qu'un créneau est acquis tant que le porteur ne l'a pas validé.
  def activity_lines
    lines = raw_activity_lines
    case price_override_placement
    when :activity    then [lines.first.merge(amount: formatted_price_override)]
    when :agreed_line then lines.map { |line| line.merge(amount: nil) }
    else lines
    end
  end

  def raw_activity_lines
    @raw_activity_lines ||= build_activity_lines
  end

  def build_activity_lines
    object.experience_bookings.active
          .includes(experience_availability: :experience)
          .sort_by { |b| [b.experience_availability&.available_on || Date.new(9999), b.experience_availability&.starts_at.to_s] }
          .map do |booking|
      availability = booking.experience_availability
      {
        name: availability&.experience&.name.presence || h.t("public.stays.items.activity"),
        date_range: activity_when(availability),
        participants: booking.participants.to_i,
        pending: booking.status == "pending",
        amount: h.humanized_money_with_symbol(Money.new(booking.price_cents.to_i))
      }
    end
  end

  # Le séjour a-t-il quoi que ce soit à montrer au client ?
  def any_public_composition?
    item_lines.any? || activity_lines.any?
  end

  # Heures d'arrivée / de départ annoncées, quand elles existent. « à partir de
  # 16 h » est l'information la plus demandée avant un séjour.
  def arrival_time_label
    object.arrival_time.presence
  end

  def departure_time_label
    object.departure_time.presence
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

  INVOICE_BADGE_STYLES = {
    "requested" => "bg-amber-100 text-amber-800",
    "sent"      => "bg-green-100 text-green-800"
  }.freeze

  # Badge de FACTURE (Michael 2026-09-02). Rien à afficher sur l'immense
  # majorité des séjours, qui ne demandent aucune facture — le badge n'apparaît
  # donc que quand une facture est attendue ou déjà partie.
  def invoice_badge
    return unless object.invoice_expected?

    h.content_tag(:span, object.invoice_status_label,
                  class: "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium #{INVOICE_BADGE_STYLES[object.invoice_status]}",
                  title: "Facture #{object.invoice_status_label.downcase}")
  end

  # Apporteur du séjour (Michael, 2026-10-18) : « Via Semisto » dans l'en-tête
  # de la fiche et dans la ligne de l'index. nil sans apporteur — rien ne
  # s'affiche pour l'immense majorité des séjours.
  def referral_badge
    return if object.referral_label.blank?

    h.content_tag(:span, "Via #{object.referral_label}",
                  class: "inline-flex items-center rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-800 ring-1 ring-inset ring-emerald-200",
                  title: "Séjour apporté par #{object.referral_label} (lien de réservation partenaire)")
  end

  # Commission due à l'apporteur (Michael, 2026-10-18) — cf.
  # `Stays::ReferralCommission`. nil sans apporteur.
  def referral_commission
    return nil if object.referral.blank?

    @referral_commission ||= Stays::ReferralCommission.new(object)
  end

  # « Commission 10 % : 41,50 € » à côté de la pastille, avec ce qui manque
  # encore quand elle n'est pas due. Affichage seul — rien n'est versé ni émis.
  def referral_commission_tag
    commission = referral_commission
    return if commission.nil?

    montant = h.humanized_money_with_symbol(Money.new(commission.amount_cents))
    if commission.due?
      h.content_tag(:span, "Commission #{commission.rate_label} : #{montant} — due",
                    class: "text-xs font-medium text-emerald-800",
                    title: "#{commission.rate_label} de l'hébergement (#{h.humanized_money_with_symbol(Money.new(commission.lodging_cents))} TVAC) — séjour confirmé et payé")
    else
      h.content_tag(:span, "Commission #{commission.rate_label} : #{montant} — pas encore due (#{commission.pending_reasons.join(', ')})",
                    class: "text-xs text-gray-600",
                    title: "Due quand le séjour est confirmé ET entièrement payé. Assiette : hébergement #{h.humanized_money_with_symbol(Money.new(commission.lodging_cents))} TVAC")
    end
  end

  # --- Données d'en-tête de la modale (Michael 2026-07-26) ------------------

  # Nombre de NUITS. nil si le séjour n'est pas daté (journée sèche, import).
  def nights_count
    return nil if object.arrival_date.blank? || object.departure_date.blank?

    (object.departure_date - object.arrival_date).to_i
  end

  # « 2 nuits · vendredi → dimanche » — le jour de la semaine compte autant que
  # la date pour qui prépare un accueil. Sur une JOURNÉE, pas de flèche : « lundi
  # → lundi » faisait chercher une seconde date à l'œil pour lui apprendre
  # qu'elle valait la première (Michael 2026-08-24).
  def stay_span_label
    nights = nights_count
    return nil if nights.nil?

    return "Journée · #{I18n.l(object.arrival_date, format: '%A')}" if nights.zero?

    jours = "#{I18n.l(object.arrival_date, format: '%A')} → #{I18n.l(object.departure_date, format: '%A')}"
    "#{nights} nuit#{'s' if nights > 1} · #{jours}"
  end

  # Occupants agrégés sur TOUS les hébergements du séjour — un groupe réparti
  # sur plusieurs gîtes doit apparaître comme un seul effectif.
  def occupants
    bookables = lodging_bookings + camping_bookings + van_bookings
    {
      adults:   bookables.sum { |b| b.try(:adults).to_i },
      children: bookables.sum { |b| b.try(:children).to_i }
    }
  end

  # Dernière édition de la NOTE interne : qui, quand. nil si la note n'a jamais
  # été touchée (import legacy).
  #
  # Depuis l'issue #313 la note est un `ActionText::RichText` : la modification se
  # pose sur CE modèle (versionné par `config/initializers/action_text_paper_trail.rb`),
  # plus sur `Stay`. D'où les deux lectures, dans cet ordre.
  #
  # LE REPLI N'EST PAS DÉCORATIF : toutes les notes écrites AVANT la migration
  # n'ont de trace que dans les versions du `Stay` (`object_changes LIKE '%notes:%'`,
  # l'ancienne colonne). Sans lui, elles perdraient toutes leur mention.
  def note_last_edit
    version = rich_note_last_version || legacy_note_last_version
    return nil if version.nil?

    { at: version.created_at, by: note_editor_name(version.whodunnit) }
  end

  # Dernière édition de la note COMPTABLE (Michael, 2026-10-19) : née en texte
  # riche, elle n'a pas d'historique d'avant à rattraper.
  def accounting_note_last_edit
    version = rich_note_last_version("accounting_notes")
    return nil if version.nil?

    { at: version.created_at, by: note_editor_name(version.whodunnit) }
  end

  # Versions du texte riche `name` (la note interne par défaut) porté par CE séjour.
  def rich_note_last_version(name = "internal_notes")
    rich_text_id = ActionText::RichText
                   .where(record_type: "Stay", record_id: object.id, name: name)
                   .pick(:id)
    return nil if rich_text_id.nil?

    PaperTrail::Version
      .where(item_type: "ActionText::RichText", item_id: rich_text_id)
      .order(created_at: :desc)
      .first
  end

  # Historique d'AVANT la bascule en texte riche : la colonne `stays.notes`
  # laissait ses versions sur le `Stay` lui-même.
  def legacy_note_last_version
    PaperTrail::Version
      .where(item_type: "Stay", item_id: object.id)
      .where("object_changes LIKE ?", "%notes:%")
      .order(created_at: :desc)
      .first
  end

  # `whodunnit` porte l'id du User. On préfère le nom du Human rattaché, à
  # défaut l'email — jamais l'id brut, illisible dans une interface.
  def note_editor_name(whodunnit)
    return nil if whodunnit.blank?

    user = User.find_by(id: whodunnit)
    user&.human&.name.presence || user&.email
  end

  # Plage de dates au format français long (ex. « 12 février 2026 »).
  # Plage de dates COMPACTÉE (Michael 2026-08-24) : ce qui est commun aux deux
  # bornes ne s'écrit qu'une fois — « 24 → 27 août 2026 » plutôt que la même
  # année et le même mois répétés, et la date seule sur une journée plutôt que
  # « 24 août 2026 → 24 août 2026 », dont la flèche promettait un intervalle
  # inexistant. La forme vit dans les YAML (scope `stay_date_range`) : la page
  # client à jeton s'affiche aussi en NL/EN, où l'ordre jour/mois diffère — ces
  # locales gardent donc les deux dates entières. On passe TOUS les paramètres à
  # chaque clé, I18n ignorant ceux qu'elle n'interpole pas.
  def date_range
    from_date = object.arrival_date
    to_date = object.departure_date
    return "—" if from_date.blank? && to_date.blank?

    # Séjour à moitié daté (import legacy) : forme brute, la borne manquante
    # reste un « ? » — il n'y a rien de commun à factoriser.
    if from_date.blank? || to_date.blank?
      from = from_date.present? ? long_date(from_date) : "?"
      to = to_date.present? ? long_date(to_date) : "?"
      return "#{from} → #{to}"
    end

    return long_date(from_date) if from_date == to_date

    key = if from_date.year != to_date.year
            :different_years
          elsif from_date.month == to_date.month
            :same_month
          else
            :same_year
          end

    h.t("stay_date_range.#{key}",
        from: long_date(from_date),
        from_day: from_date.day,
        from_short: h.l(from_date, format: :short).strip,
        to: long_date(to_date))
  end

  # `:long` vaut « %e %B %Y » en FR : %e cale les jours à un chiffre sur deux
  # colonnes, d'où l'espace de tête à retirer avant de coller la date à une flèche.
  def long_date(date)
    h.l(date, format: :long).strip
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

  # Pictogramme d'une ligne de composition (jeu `FunnelIconsHelper`). Le sens
  # reste porté par le texte à côté — l'icône n'est là que pour donner un rythme
  # visuel à la liste et rendre un séjour composite lisible d'un coup d'œil.
  def line_icon(bookable_type, bookable)
    case bookable_type
    when "Booking"        then :house
    when "SpaceBooking"   then :hall
    when "CampingBooking" then bookable.try(:kind) == "terrasse" ? :leaf : :tent
    when "VanBooking"     then :van
    when "HamacBooking"   then :hammock
    else :sparkles
    end
  end

  # « samedi 12 septembre 2026, 14:00 » — la date ET l'heure, parce qu'une
  # activité se rate à l'heure près.
  def activity_when(availability)
    return nil if availability.nil? || availability.available_on.blank?

    jour = h.l(availability.available_on, format: :long)
    availability.starts_at.present? ? "#{jour} à #{availability.starts_at}" : jour
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
    # Sans réservable (séjour vide, activité seule, repas seuls) : le client.
    return display_name.presence || "—" if primary_bookable.nil?
    person = [primary_bookable.try(:firstname), primary_bookable.try(:lastname)].compact_blank.join(" ")
    group = primary_bookable.try(:group_name).presence
    [person.presence, group].compact.join(" · ").presence || "—"
  end

  # Bloc « Vos informations » de la page client (Michael, 2026-10-19). Il lisait
  # `contact_line`, donc le seul réservable : un séjour sans hébergement ni
  # espace (une activité seule, des repas) n'en a pas, et la page affichait
  # « — » alors que le client avait un nom et une adresse (séjour #1554).
  #
  # Le CLIENT est la source : son nom, son email, son téléphone. Le nom de la
  # personne ou du groupe porté par la réservation s'y ajoute quand il dit autre
  # chose. Sur un client FOURRE-TOUT, rien du client ne sort (nom et boîte sont
  # ceux des 4 Sources) : seule la réservation d'origine parle.
  # Rend { name:, email:, phone: } ; `name` vaut « — » quand on ne sait rien.
  def public_contact
    origin = origin_contacts.first || {}
    customer = catch_all_customer? ? nil : object.customer

    names = [customer&.explicit_name, origin[:name], origin[:group]].compact_blank
    names = names.uniq { |n| n.strip.downcase }

    { name:  names.join(" · ").presence || "—",
      email: customer ? customer.email.presence : origin[:email],
      phone: customer&.phone.presence || origin[:phone] }
  end

  # --- Ventilation du montant exigible (epic #55, Phase 3) ---------------
  # Montants formatés en euros pour la page client. On lit l'arithmétique du
  # modèle (source unique de vérité « total prévu vs exigible »).

  def formatted_amount_paid
    money(object.amount_paid_cents)
  end

  # La Pizza Party a sa propre ligne dans la ventilation : on la sort de
  # « Hébergement & espaces », où elle tombait faute d'autre case.
  def formatted_lodging_and_spaces
    money(object.lodging_and_spaces_amount_cents - object.party_reservations_amount_cents)
  end

  def has_party_reservations? = object.party_reservations_amount_cents.positive?

  def formatted_party_reservations
    money(object.party_reservations_amount_cents)
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

  # Demande DÉPOSÉE, pas encore regardée. Depuis l'inversion de l'ordre (issue
  # #215) le funnel n'encaisse plus rien : il enregistre une demande que le Pôle
  # Accueil examine, et c'est la PRÉ-CONFIRMATION qui pose l'acompte et son lien
  # de paiement. Tant que ce regard humain n'a pas eu lieu, rien n'est dû —
  # l'équipe peut encore ajuster le séjour, ou le refuser.
  #
  # La page client réclamait pourtant « Payer le solde de 1 685 € » sous un badge
  # « En attente de paiement », sur une demande que personne n'avait encore lue :
  # qui payait là réglait un séjour qui n'existait pas.
  def awaiting_review?
    object.status == "pending"
  end

  # Faut-il afficher le bloc de ventilation du solde ? Dès qu'il y a quelque
  # chose à dire : un exigible à régler, un encaissé à créditer, ou des
  # activités en attente à signaler.
  # Demande EN ATTENTE : rien n'est dû avant la pré-confirmation (cf.
  # `awaiting_review?`) — ventiler un solde qui n'est pas réclamé n'a rien à dire.
  # Séjour ANNULÉ : plus rien d'exigible — la section ne sert qu'à montrer ce
  # qui a déjà été encaissé (à rembourser ou retenir), sinon elle disparaît.
  def show_balance_section?
    return false if awaiting_review?
    return object.amount_paid_cents.positive? if object.canceled?

    object.payable_now? ||
      object.amount_paid_cents.positive? ||
      has_pending_experiences?
  end

  # Bouton « Payer le solde » : un exigible strictement positif ET aucun
  # paiement `pending` déjà en cours (l'acompte non réglé, par exemple, est déjà
  # couvert par son propre CTA — on n'empile pas deux boutons pour la même dette).
  # Jamais sur une demande EN ATTENTE ni sur un séjour ANNULÉ : dans les deux cas
  # plus rien n'est exigible, quoi qu'en dise le total.
  def show_balance_cta?
    return false if awaiting_review?

    !object.canceled? && object.payable_now? && object.payments.pending.none?
  end

  # --- Paiement par virement (Michael, 2026-10-19) ---
  # Le compte qui reçoit les séjours, déjà affiché sur l'ancienne page booking.
  BANK_TRANSFER = { holder: "Les 4 Sources", iban: "BE72 5230 8060 1116", bic: "TRIOBEBB" }.freeze

  # La communication que l'affectation automatique reconnaît (`Finance::MatchStay`).
  def transfer_communication
    Finance::MatchStay.communication_for(object)
  end

  # Le montant à virer : celui du paiement en attente (l'acompte demandé à la
  # pré-confirmation), sinon le solde exigible. Les mêmes cas que les boutons
  # de paiement en ligne : rien sur une demande en attente, un séjour annulé ou
  # un séjour payé sur une plateforme.
  def transfer_amount_cents
    return 0 if awaiting_review? || object.canceled? || object.ota?

    pending = object.payments.pending.sum(:amount_cents)
    return pending if pending.positive?

    object.payable_now? ? object.balance_due_cents : 0
  end

  # Au centime près, comme sur un formulaire de virement (« 186,00 € »).
  def formatted_transfer_amount
    h.number_to_currency(transfer_amount_cents / 100.0)
  end

  def show_transfer?
    transfer_amount_cents.positive?
  end

  # Le client a signalé un virement que nous n'avons pas encore vu arriver :
  # aucun paiement encaissé depuis son signalement. Dès qu'un paiement l'est, le
  # bouton revient pour le virement suivant (le solde après l'acompte).
  def transfer_notice_pending?
    notified_at = object.transfer_notified_at
    return false if notified_at.nil?

    object.payments.paid.where("updated_at > ?", notified_at).none?
  end

  def formatted_transfer_notified_amount
    h.number_to_currency(object.transfer_notified_cents.to_i / 100.0)
  end

  def formatted_transfer_notified_on
    h.l(object.transfer_notified_at.to_date, format: :long)
  end

  private

  def money(cents)
    h.humanized_money_with_symbol(Money.new(cents.to_i))
  end
end
