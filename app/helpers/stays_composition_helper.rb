module StaysCompositionHelper
  # Une icône emoji PAR TYPE de ressource composant un séjour, dans un ordre fixe
  # et stable : hébergement, salle, cuisine, van, tente, activité. Jamais une
  # icône par occurrence — une seule par type présent. Chaque icône porte un
  # `title` (tooltip natif) nommant la ressource.
  #
  # HAMAC : aucune icône. Les hamacs ne sont PAS persistés côté séjour — ils
  # n'existent que dans le devis B2C (`Reservations::Draft#hamacs`, pour le
  # prix) ; `CampingBooking` ne persiste jamais que `kind: "tente"` et
  # `RentalItem` n'est qu'un catalogue d'objets physiques (jamais rattaché à un
  # Stay). Dès qu'un stockage hamac côté séjour existera, ajouter 🛌 ici.
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
    icons << composition_icon("🎯", "Activité")     if stay_has_activity?(stay)
    return if icons.empty?

    tag.span(safe_join(icons, " "), class: "inline-flex items-center gap-1")
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

  # Camping = tente (seul `kind` persisté aujourd'hui — cf. note hamac ci-dessus).
  def stay_has_tent?(stay)
    stay_items_of(stay, "CampingBooking").any?
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
