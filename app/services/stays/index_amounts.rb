module Stays
  # Agrégats monétaires de l'index Séjours (epic #81) — encaissé + reste dû
  # exigible, calculés EN LOT pour la page courante (≤ 30 séjours) afin d'éviter
  # tout N+1.
  #
  # Le point dur : `Stay#payments` n'est PAS une association mais une requête
  # construite à la volée (union `payments.stay_id` ∪ `payments.booking_id` des
  # items Booking). Aucun preload ne peut donc l'aplatir — on reconstitue ici la
  # MÊME union en UNE seule requête pour toute la page, puis on ventile en Ruby.
  #
  # Le reste (total, activités `pending`, prix imposé) se lit sur des
  # associations DÉJÀ préchargées par le contrôleur (`experience_bookings` +
  # `experience_availability` + `experience` pour le calcul `price_cents`),
  # donc sans requête supplémentaire.
  class IndexAmounts
    # Statuts d'activité écartés du total exigible (miroir de `ExperienceBooking`).
    Result = Struct.new(:paid_cents, :balance_due_cents, keyword_init: true)

    def initialize(stays)
      @stays = stays.to_a
    end

    # => { stay_id => Result(paid_cents:, balance_due_cents:) }
    def call
      paid = paid_by_stay
      @stays.each_with_object({}) do |stay, acc|
        paid_cents = paid[stay.id].to_i
        acc[stay.id] = Result.new(
          paid_cents:       paid_cents,
          balance_due_cents: payable_cents(stay) - paid_cents
        )
      end
    end

    private

    # Assiette exigible d'un séjour, dérivée du total (source unique de vérité,
    # cf. `Stay#payable_amount_cents`) : sous prix imposé le total est ferme ;
    # sinon on retranche les activités encore `pending` (non facturables).
    def payable_cents(stay)
      return stay.total_amount_cents.to_i if stay.price_overridden?

      stay.total_amount_cents.to_i - pending_experiences_cents(stay)
    end

    # Somme des activités `pending` LUES en mémoire (association préchargée) —
    # jamais `experience_bookings.pending` (scope = requête). `price_cents`
    # délègue à `experience` (préchargé) : aucun accès base.
    def pending_experiences_cents(stay)
      stay.experience_bookings
          .select { |eb| eb.status == "pending" }
          .sum(&:price_cents)
    end

    # Encaissé (paiements `paid`) par séjour, reconstituant l'union du modèle en
    # une requête. Chaque paiement est attribué UNE fois : d'abord par son
    # `stay_id` direct, à défaut via le `booking_id` de l'un de ses items.
    def paid_by_stay
      return {} if @stays.empty?

      stay_ids     = @stays.map(&:id)
      booking2stay = booking_to_stay
      booking_ids  = booking2stay.keys

      totals = Hash.new(0)
      paid_payments(stay_ids, booking_ids).each do |payment|
        stay_id =
          if payment.stay_id && stay_ids.include?(payment.stay_id)
            payment.stay_id
          else
            booking2stay[payment.booking_id]
          end
        next unless stay_id

        totals[stay_id] += payment.amount_cents.to_i
      end
      totals
    end

    # Carte bookable(Booking)#id => stay_id, lue sur les `stay_items` préchargés.
    def booking_to_stay
      @stays.each_with_object({}) do |stay, map|
        stay.stay_items.each do |item|
          map[item.bookable_id] = stay.id if item.bookable_type == "Booking"
        end
      end
    end

    # Union `stay_id ∈ page` ∪ `booking_id ∈ items Booking de la page`, restreinte
    # aux paiements encaissés (le default_scope soft-deletion exclut les supprimés).
    def paid_payments(stay_ids, booking_ids)
      relation = Payment.paid.where(stay_id: stay_ids)
      relation = relation.or(Payment.paid.where(booking_id: booking_ids)) if booking_ids.any?
      relation.select(:id, :amount_cents, :stay_id, :booking_id)
    end
  end
end
