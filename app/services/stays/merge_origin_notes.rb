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
  # TEXTE RICHE depuis l'issue #313 : la note du séjour est un `ActionText`, les
  # notes des bookables restent des colonnes de texte brut. On assemble donc des
  # BLOCS HTML, chaque note d'origine étant convertie par `InternalNote.to_html`.
  #
  # IDEMPOTENT : une note déjà rapatriée est reconnue par comparaison de son TEXTE
  # BRUT normalisé (espaces et fins de ligne écrasés) — jamais du HTML, sans quoi
  # une simple différence de balisage recopierait une note déjà présente. Rejouer
  # le backfill ne duplique donc rien.
  class MergeOriginNotes
    SEPARATOR = "\n\n".freeze

    def self.call(stay)
      new(stay).call
    end

    # HTML fusionné, sans rien écrire — sert aussi à la création d'un séjour,
    # où le stay n'existe pas encore.
    def self.merged_html(stay)
      new(stay).merged_html
    end

    # Le rapatriement écrirait-il quelque chose ? Le dry-run de la rake.
    def self.pending?(stay)
      new(stay).pending?
    end

    def initialize(stay)
      @stay = stay
    end

    # Retourne true si la note du séjour a changé, false si elle contenait déjà
    # tout.
    #
    # `Stay.no_touching` : `ActionText::RichText belongs_to :record, touch: true`,
    # donc enregistrer la note toucherait `stays.updated_at`. Ce rapatriement n'est
    # pas une modification éditoriale — il ne doit ni horodater le séjour ni
    # déclencher ses callbacks de recalcul. C'est ce que faisait `update_column`
    # avant la bascule en texte riche.
    def call
      return false unless pending?

      html = merged_html

      Stay.no_touching do
        rich = @stay.internal_notes
        rich.body = html
        rich.save!
      end

      true
    end

    def pending?
      normalize(InternalNote.plain_text(merged_html)) != normalize(current_plain)
    end

    def merged_html
      html_parts = []
      plain_parts = []

      if InternalNote.present?(current_html)
        html_parts << current_html
        plain_parts << current_plain
      end

      origin_notes.each do |note|
        next if plain_parts.any? { |part| normalize(part).include?(normalize(note)) }

        html_parts << InternalNote.to_html(note)
        plain_parts << note
      end

      html_parts.join
    end

    private

    def current_html
      @current_html ||= InternalNote.html_for(@stay)
    end

    def current_plain
      @current_plain ||= InternalNote.plain_text(current_html)
    end

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
