module Stays
  # Rapatrie dans la note du SÉJOUR les notes portées par ses réservations
  # d'origine (Michael 2026-08-24). La modale affichait jusqu'ici la note du
  # séjour PUIS, en dessous et en lecture seule, celles du Booking / SpaceBooking :
  # trois blocs à lire pour une seule information, dont deux qu'on ne pouvait pas
  # corriger. Après passage de ce service il n'existe plus qu'une note, éditable.
  #
  # N'ÉCRIT JAMAIS SUR LE BOOKABLE : la note d'origine reste sur la réservation,
  # qui garde ce que le client a écrit au moment de réserver. On y ajoute, on n'y
  # retire rien.
  #
  # IDEMPOTENT : une note déjà rapatriée est reconnue par comparaison de son texte
  # normalisé (espaces et fins de ligne écrasés) et n'est pas recopiée une seconde
  # fois. Rejouer le backfill ne duplique donc rien.
  class MergeOriginNotes
    SEPARATOR = "\n\n".freeze

    def self.call(stay)
      new(stay).call
    end

    # Texte fusionné, sans rien écrire — sert aussi à la création d'un séjour,
    # où le stay n'existe pas encore.
    def self.merged_text(stay)
      new(stay).merged_text
    end

    def initialize(stay)
      @stay = stay
    end

    # Retourne true si la note du séjour a changé, false si elle contenait déjà
    # tout. `update_column` : ce rapatriement n'est pas une modification
    # éditoriale, il ne doit ni toucher `updated_at` ni déclencher les callbacks
    # de recalcul du séjour.
    def call
      texte = merged_text
      return false if texte == @stay.notes.to_s

      @stay.update_column(:notes, texte)
      true
    end

    def merged_text
      parts = [@stay.notes.to_s.strip].reject(&:blank?)

      origin_notes.each do |note|
        next if parts.any? { |part| normalize(part).include?(normalize(note)) }

        parts << note
      end

      parts.join(SEPARATOR)
    end

    private

    # Notes des bookables, dans l'ordre des stay_items, dédoublonnées entre elles
    # — un groupe qui réserve un gîte ET une salle a souvent saisi le même
    # commentaire sur les deux formulaires.
    def origin_notes
      @stay.stay_items.filter_map { |item| item.bookable.try(:notes).presence&.strip }
           .uniq { |note| normalize(note) }
    end

    # Comparaison INSENSIBLE à la mise en forme : le même texte recopié à la main
    # dans la note du séjour, avec un retour à la ligne en plus, ne doit pas
    # compter pour une note manquante.
    def normalize(text)
      text.to_s.gsub(/\s+/, " ").strip.downcase
    end
  end
end
