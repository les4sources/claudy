# Helpers de présentation des séjours (epic #81, Phase 3).
module StaysHelper
  # Libellés français des canaux d'attribution (`Stay::SOURCES`). Partagés entre
  # le form séjour, l'index « Séjours récents » et son filtre.
  SOURCE_LABELS = {
    "manual"       => "Saisie manuelle",
    "ota"          => "OTA (Airbnb / Booking.com)",
    "reservation"  => "Réservation en ligne",
    "tally_legacy" => "Import Tally (legacy)"
  }.freeze

  def stay_source_label(value)
    SOURCE_LABELS[value.to_s] || value.to_s
  end

  # Libellé FR d'un statut de séjour. Source unique : `StayDecorator::STATUS_STYLES`,
  # qui porte déjà les libellés des badges — un second dictionnaire dériverait.
  # Repli sur la valeur brute pour un statut historique inconnu.
  def stay_status_label(value)
    StayDecorator::STATUS_STYLES.dig(value.to_s, :label) || value.to_s
  end

  # Teinte de fond LÉGÈRE d'une ligne de l'index, par statut (Michael
  # 2026-07-26). Palier `-50` plein : c'est la nuance la plus claire de Tailwind,
  # donc déjà discrète, mais PERCEPTIBLE. Une première version à `-50/60`
  # (opacité 60 %) rendait un `rgba(243,250,247,.6)` indistinguable du blanc au
  # navigateur — une teinte de statut qu'on ne voit pas ne sert à rien.
  #
  # Le `hover:` monte d'un palier (`-100`) et est redéfini par statut, sinon le
  # `hover:bg-gray-50` générique effacerait la teinte au survol.
  ROW_STATUS_CLASSES = {
    "confirmed"     => "bg-green-50 hover:bg-green-100",
    "pre_confirmed" => "bg-indigo-50 hover:bg-indigo-100",
    "pending"       => "bg-amber-50 hover:bg-amber-100",
    "canceled"      => "bg-red-50 hover:bg-red-100 text-gray-400",
    "cancelled"     => "bg-red-50 hover:bg-red-100 text-gray-400"
  }.freeze

  def stay_row_classes(stay)
    ROW_STATUS_CLASSES.fetch(stay.status.to_s, "bg-white hover:bg-gray-50")
  end

  # --- Déroulé du séjour (modale, Michael 2026-07-26) ------------------------
  # Arrivée, activités datées, départ : la forme du séjour DANS LE TEMPS, ce
  # qu'une liste de lignes de composition ne dit pas.
  #
  # Aucune requête : on lit `stay_items`, `experience_bookings` et `meal_orders`,
  # tous préchargés par le contrôleur.
  def stay_timeline(stay)
    return stay_day_timeline(stay) if stay_single_day?(stay)

    jalons = []

    if stay.arrival_date
      lieu = stay.lodging_bookings.filter_map { |b| b.lodging&.name }.uniq.join(", ").presence
      heure, annonce = arrival_hour_and_note(stay)
      jalons << { date: stay.arrival_date,
                  title: "#{l(stay.arrival_date, format: :long).capitalize}#{heure.present? ? " · #{heure}" : ''} — Arrivée",
                  detail: lieu,
                  note: annonce }
    end

    stay.experience_bookings.reject { |eb| eb.cancelled? || eb.refused? }.each do |eb|
      creneau = eb.experience_availability
      next if creneau&.available_on.blank?

      jalons << { date: creneau.available_on,
                  title: "#{l(creneau.available_on, format: :long).capitalize} — #{creneau.experience&.name}",
                  detail: "#{eb.participants} participant(s)" }
    end

    stay.meals.each do |repas|
      next if repas.date.blank?

      jalons << { date: repas.date,
                  title: "#{l(repas.date, format: :long).capitalize} — #{repas.label}",
                  detail: "#{repas.people} personne(s)" }
    end

    if stay.departure_date
      jalons << { date: stay.departure_date,
                  title: "#{l(stay.departure_date, format: :long).capitalize}#{stay.departure_time.present? ? " · #{stay.departure_time}" : ''} — Départ",
                  detail: nil,
                  note: nil }
    end

    jalons.sort_by { |j| j[:date] }
  end

  # --- Séjour sur une seule journée (Michael, 2026-10-18) --------------------
  # Arrivée et départ le même jour : deux lignes qui répètent la date ne disent
  # rien de plus qu'une seule. La journée tient donc en un jalon, « 1 octobre
  # 2026 · 9h30 → 14h », et ce qui se passe entre les deux (activités, repas)
  # suit en dessous, avec son heure seule — la date est déjà dite.
  def stay_single_day?(stay)
    stay.arrival_date.present? && stay.arrival_date == stay.departure_date
  end

  # Ordre d'un repas dans la journée, faute d'heure : le moment suffit.
  MOMENT_MINUTES = { "midi" => 12 * 60, "gouter" => 16 * 60, "soir" => 19 * 60 }.freeze

  def stay_day_timeline(stay)
    jour = stay.arrival_date
    heure, annonce = arrival_hour_and_note(stay)
    plage = [heure, stay.departure_time.presence]
    horaire = if plage.all?
                "#{plage[0]} → #{plage[1]}"
              elsif plage[0]
                plage[0]
              elsif plage[1]
                "jusqu'à #{plage[1]}"
              end

    # Un séjour d'une journée occupe plus souvent une salle qu'un gîte : le
    # lieu, c'est l'un comme l'autre.
    lieux = stay.lodging_bookings.filter_map { |b| b.lodging&.name } +
            stay.space_bookings.flat_map { |b| b.spaces.map(&:name) }

    etapes = []

    stay.experience_bookings.reject { |eb| eb.cancelled? || eb.refused? }.each do |eb|
      creneau = eb.experience_availability
      next unless creneau&.available_on == jour

      debut = creneau.starts_at_minutes
      etapes << { date: jour, minutes: debut,
                  title: [stay_timeline_hour(debut), creneau.experience&.name].compact.join(" — "),
                  detail: "#{eb.participants} participant(s)" }
    end

    stay.meals.each do |repas|
      next unless repas.date == jour

      # « Repas (midi ou soir) » : la parenthèse sert au formulaire ; ici le
      # moment est connu, c'est lui qu'on dit.
      nom = repas.label.sub(/\s*\(.*\)\z/, "")
      moment = repas.moment_label
      etapes << { date: jour, minutes: MOMENT_MINUTES[repas.moment.to_s],
                  title: moment && moment != nom ? "#{nom} (#{moment.downcase})" : nom,
                  detail: "#{repas.people} personne(s)" }
    end

    journee = { date: jour,
                title: [l(jour, format: :long).capitalize, horaire].compact.join(" · "),
                detail: lieux.uniq.join(", ").presence,
                note: annonce }

    [journee] + etapes.sort_by { |e| e[:minutes] || 24 * 60 }
  end

  # « 09:30 » → « 9h30 », « 14:00 » → « 14h » : comme on écrit l'heure
  # d'arrivée.
  def stay_timeline_hour(minutes)
    return if minutes.nil?

    heures, reste = minutes.divmod(60)
    reste.zero? ? "#{heures}h" : format("%dh%02d", heures, reste)
  end

  # L'heure d'arrivée vient de DEUX endroits, et les deux comptent pour qui
  # accueille : celle qu'on note en interne (`Stay#arrival_time`) et celle que
  # le client annonce lui-même depuis sa page (`Booking#estimated_arrival`).
  #
  # La seconde est du texte libre, et elle l'est vraiment : « 16h », mais aussi
  # « 16-18h » ou « Après 18h car ils s'installent d'abord à leur évènement ».
  # C'est la longueur qui décide où elle va — une heure courte tient dans le
  # titre du jalon, une phrase se lit en dessous. La tronquer serait pire que
  # de la déplacer : c'est précisément la fin qui porte la raison.
  HEURE_COURTE = 12

  def arrival_hour_and_note(stay)
    annoncees = stay.lodging_bookings.filter_map { |b| b.estimated_arrival.presence }.uniq
    interne = stay.arrival_time.presence

    heure = interne || annoncees.find { |h| h.length <= HEURE_COURTE }
    restantes = annoncees - [heure]
    note = restantes.any? ? "Arrivée annoncée : #{restantes.join(' · ')}" : nil

    [heure, note]
  end

  # Marqueur d'une section dépliable du formulaire séjour (Michael 2026-07-26).
  # Il dit d'un coup d'œil, section repliée, s'il y a quelque chose dedans — sans
  # quoi il faudrait toutes les ouvrir pour savoir ce que contient le séjour.
  # `count` est optionnel : certains blocs (hébergement) n'ont pas de cardinal
  # parlant.
  def stay_form_section_marker(defined, count = nil)
    if defined
      libelle = count.to_i.positive? ? "#{count} défini#{'s' if count.to_i > 1}" : "défini"
      tag.span(libelle, class: "rounded-full bg-indigo-50 px-2 py-0.5 text-xs font-medium text-indigo-700")
    else
      tag.span("+ ajouter", class: "text-xs font-normal text-gray-400")
    end
  end
end
