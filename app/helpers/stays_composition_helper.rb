module StaysCompositionHelper
  # (Vue fiche client.) Une icône emoji PAR TYPE de ressource composant un
  # séjour, dans un ordre fixe et stable. L'index Séjours utilise, lui,
  # `stay_composition_icon_row` plus bas (emplacements fixes, SVG). Jamais une
  # icône par occurrence — une seule par type présent. Chaque icône porte un
  # `title` (tooltip natif) nommant la ressource.
  #
  # HAMAC : 🛌, depuis l'issue #138 — les hamacs sont désormais persistés sur le
  # séjour (`HamacBooking` via `StayItem`), plus seulement présents dans le devis.
  #
  # PERFORMANCE : ne déclenche AUCUNE requête. S'appuie sur les associations
  # préchargées par `CustomersController#show` (stay_items→bookable,
  # space_reservations→space, experience_bookings). Tout le filtrage se fait en
  # mémoire Ruby — pas de N+1 dans la liste des séjours.
  def stay_composition_icons(stay)
    icons = []
    icons << composition_icon("🏠", "Hébergement") if stay_has_lodging?(stay)
    icons << composition_icon("🏛️", "Salle")       if stay_has_hall?(stay)
    icons << composition_icon("🍳", "Cuisine")      if stay_has_kitchen?(stay)
    icons << composition_icon("🚐", "Van")          if stay_has_van?(stay)
    icons << composition_icon("⛺", "Tente")        if stay_has_tent?(stay)
    icons << composition_icon("🛌", "Hamac")        if stay_has_hamac?(stay)
    icons << composition_icon("🪑", "Terrasse")     if stay_has_terrace?(stay)
    icons << composition_icon("🎯", "Activité")     if stay_has_activity?(stay)
    return if icons.empty?

    tag.span(safe_join(icons, " "), class: "inline-flex items-center gap-1")
  end

  # --- Rangée d'icônes à emplacements FIXES (index Séjours, Michael 2026-07-26)
  #
  # Différence avec `stay_composition_icons` ci-dessus, qui n'affiche QUE les
  # types présents : ici les SIX emplacements sont TOUJOURS rendus, gris clair
  # par défaut et colorés quand le séjour contient l'élément. Les colonnes
  # restent ainsi alignées d'une ligne à l'autre — on lit la composition d'un
  # coup d'œil vertical, ce qu'une liste à longueur variable ne permet pas.
  #
  # Le CAMPING-CAR a son emplacement propre (Michael 2026-07-26). L'emplacement
  # « tente » couvre donc le reste du plein air — tente, hamac, terrasse — pour
  # qu'aucune composition ne soit invisible ; son tooltip nomme ce qui est
  # réellement présent.
  #
  # PERFORMANCE : aucun accès base — mêmes prédicats en mémoire que ci-dessus.
  COMPOSITION_SLOTS = %i[lodging outdoor van hall kitchen activity].freeze

  def stay_composition_icon_row(stay)
    icons = COMPOSITION_SLOTS.map { |slot| composition_slot_icon(slot, stay) }
    tag.span(safe_join(icons), class: "inline-flex items-center gap-1.5")
  end

  private

  def composition_slot_icon(slot, stay)
    active = composition_slot_active?(slot, stay)
    label  = composition_slot_label(slot, stay, active)
    classes = active ? "text-indigo-600" : "text-gray-200"

    tag.span(composition_slot_svg(slot),
             class: "#{classes} transition-colors",
             title: label, role: "img", aria: { label: label })
  end

  def composition_slot_active?(slot, stay)
    case slot
    when :lodging  then stay_has_lodging?(stay)
    when :outdoor  then stay_has_tent?(stay) || stay_has_hamac?(stay) || stay_has_terrace?(stay)
    when :van      then stay_has_van?(stay)
    when :hall     then stay_has_hall?(stay)
    when :kitchen  then stay_has_kitchen?(stay)
    when :activity then stay_has_activity?(stay)
    end
  end

  SLOT_LABELS = {
    lodging:  "Hébergement",
    outdoor:  "Tente (ou hamac / terrasse)",
    van:      "Camping-car",
    hall:     "Salle",
    kitchen:  "Cuisine",
    activity: "Activité"
  }.freeze

  # Tooltip : le libellé du slot, précisé pour le plein air (on nomme ce qui est
  # RÉELLEMENT présent), et suffixé « — non compris » quand l'icône est éteinte.
  def composition_slot_label(slot, stay, active)
    base = SLOT_LABELS[slot]
    base = outdoor_detail_label(stay) if slot == :outdoor && active
    active ? base : "#{SLOT_LABELS[slot]} — non compris"
  end

  def outdoor_detail_label(stay)
    parts = []
    parts << "Tente"    if stay_has_tent?(stay)
    parts << "Hamac"    if stay_has_hamac?(stay)
    parts << "Terrasse" if stay_has_terrace?(stay)
    parts.join(" · ").presence || SLOT_LABELS[:outdoor]
  end

  # SVG inline en trait (stroke currentColor) plutôt qu'emoji : dans un tableau
  # dense, 5 emojis par ligne × 30 lignes deviennent du bruit, et un emoji ne se
  # « désature » pas proprement. Le trait suit la couleur du slot.
  SLOT_PATHS = {
    # Hébergement : un LIT (Michael 2026-07-26) — une maison désignait le bâti,
    # pas le couchage. C'est le MÊME tracé que l'entrée « Séjours » de la nav :
    # même objet, même icône dans toute l'app.
    lodging:  "M2 20v-8a2 2 0 012-2h16a2 2 0 012 2v8M4 10V6a2 2 0 012-2h12a2 2 0 012 2v4M12 4v6M2 18h20",
    # Tente / plein air
    outdoor:  "M12 3.75L3 20.25h18L12 3.75zm0 0v16.5",
    # Salle (bâtiment / colonnes)
    hall:     "M3.75 21h16.5M4.5 3h15M5.25 3v18m13.5-18v18M9 6.75h6M9 11.25h6M9 15.75h6",
    # Camping-car : caisse + capot + deux roues.
    van:      "M2 16V7a1 1 0 011-1h11v4h4l3 3v3h-2m-4 0H9m-4 0H2M9 17a2 2 0 11-4 0 2 2 0 014 0z" \
              "M19 17a2 2 0 11-4 0 2 2 0 014 0z",
    # Cuisine : ASSIETTE vue de dessus (Michael 2026-07-26) — deux cercles
    # concentriques, plus lisible à 16 px que des ustensiles entrelacés.
    kitchen:  "M21 12a9 9 0 11-18 0 9 9 0 0118 0zM17 12a5 5 0 11-10 0 5 5 0 0110 0z",
    # Activité (étoile / cible)
    activity: "M11.48 3.5a.562.562 0 011.04 0l2.125 5.111a.563.563 0 00.475.345l5.518.442c.499.04.701.663.321.988l" \
              "-4.204 3.602a.563.563 0 00-.182.557l1.285 5.385a.562.562 0 01-.84.61l-4.725-2.885a.562.562 0 " \
              "00-.586 0L6.982 20.54a.562.562 0 01-.84-.61l1.285-5.386a.562.562 0 00-.182-.557l-4.204-3.602a.563.563 " \
              "0 01.321-.988l5.518-.442a.563.563 0 00.475-.345L11.48 3.5z"
  }.freeze

  def composition_slot_svg(slot)
    tag.svg(
      tag.path(nil, "stroke-linecap": "round", "stroke-linejoin": "round", d: SLOT_PATHS[slot]),
      class: "w-4 h-4", fill: "none", viewBox: "0 0 24 24",
      stroke: "currentColor", "stroke-width": "1.5", "aria-hidden": "true"
    )
  end

  public

  # Libellé de la ou des nuits couvertes par un réservable plein air (camping /
  # van), fenêtre `[from, to)`. Sert à distinguer les PLAGES d'un même séjour
  # quand le camping/van varie d'une nuit à l'autre (grille par nuit, Michael
  # 2026-07-20) : « Nuit du 12 août » ou « Du 12 au 14 août ». nil si pas de dates.
  def outdoor_nights_label(booking)
    from = booking.try(:from_date)
    to   = booking.try(:to_date)
    return nil if from.blank? || to.blank?
    last = to - 1
    return "Nuit du #{l(from, format: :long)}" if last <= from
    "Du #{l(from, format: :long)} au #{l(last, format: :long)}"
  end

  private

  def composition_icon(emoji, label)
    tag.span(emoji, title: label, role: "img", aria: { label: label },
                    class: "text-base leading-none")
  end

  # StayItems du type polymorphe demandé (les soft-deleted sont déjà exclus par
  # le default_scope au moment du préchargement).
  def stay_items_of(stay, bookable_type)
    stay.stay_items.select { |item| item.bookable_type == bookable_type }
  end

  def stay_has_lodging?(stay)
    stay_items_of(stay, "Booking").any?
  end

  def stay_has_van?(stay)
    stay_items_of(stay, "VanBooking").any?
  end

  # Camping = tente. Un `CampingBooking` peut aussi être une TERRASSE (kind
  # "terrasse", décision Michael 2026-07-20) : on distingue par `kind`.
  def stay_has_tent?(stay)
    stay_items_of(stay, "CampingBooking").any? { |i| i.bookable&.kind != "terrasse" }
  end

  # Hamac = location persistée sur le séjour (issue #138).
  def stay_has_hamac?(stay)
    stay_items_of(stay, "HamacBooking").any?
  end

  # Terrasse = occupation de jour (kind "terrasse") — icône dédiée 🪑.
  def stay_has_terrace?(stay)
    stay_items_of(stay, "CampingBooking").any? { |i| i.bookable&.kind == "terrasse" }
  end

  # Activité = au moins un ExperienceBooking ACTIF (ni annulé, ni refusé — même
  # définition que le scope `ExperienceBooking.active`, appliquée en mémoire pour
  # rester sans requête sur une association préchargée).
  def stay_has_activity?(stay)
    stay.experience_bookings.any? { |eb| !(eb.cancelled? || eb.refused?) }
  end

  # Tous les espaces occupés par les SpaceBooking du séjour.
  def stay_spaces(stay)
    stay_items_of(stay, "SpaceBooking")
      .filter_map(&:bookable)
      .flat_map(&:space_reservations)
      .filter_map(&:space)
  end

  # Distinction salle vs cuisine par MOTIF sur code + nom (les codes réels de prod
  # — « Cuisine », « Grande salle », « Coworking », « Bois », « OUEST »… — varient
  # et ne suivent pas les codes des seeds : on résout par pattern, pas par liste
  # figée). Un espace « Cuisine » → 🍳 ; tout le reste (salles, coworking, bois,
  # pâtures/extérieur) → icône salle générique 🏛️.
  KITCHEN_SPACE_PATTERN = /cuisine/i

  def kitchen_space?(space)
    "#{space.code} #{space.name}".match?(KITCHEN_SPACE_PATTERN)
  end

  def stay_has_kitchen?(stay)
    stay_spaces(stay).any? { |space| kitchen_space?(space) }
  end

  def stay_has_hall?(stay)
    stay_spaces(stay).any? { |space| !kitchen_space?(space) }
  end
end
