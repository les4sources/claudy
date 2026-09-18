module CarrierStatements
  # Ce qu'un porteur a tenu et qui n'a pas encore été relevé (epic #244, phase 3).
  #
  # « Pas encore relevé » est la condition qui compte : une prestation relevée
  # une fois est payée une fois. La table des lignes porte un index UNIQUE sur
  # `experience_booking_id` — ce service évite simplement de proposer ce que cet
  # index refuserait.
  class Selection
    attr_reader :human, :period_from, :period_to

    def initialize(human:, period_from: nil, period_to: nil)
      @human = human
      @period_from = period_from
      @period_to = period_to
    end

    def bookings
      @bookings ||= begin
        scope = ExperienceBooking.held
                                 .for_carrier(human)
                                 .where.not(id: already_reported_ids)
                                 .includes(:experience_availability, experience_availability: :experience)
        scope = scope.where(experience_availabilities: { available_on: period_from.. }) if period_from
        scope = scope.where(experience_availabilities: { available_on: ..period_to }) if period_to
        scope.to_a.sort_by { |b| [b.experience_availability&.available_on || Date.new(0), b.id] }
      end
    end

    def total_fee_cents = bookings.sum { |b| b.carrier_fee_cents.to_i }

    def any? = bookings.any?

    private

    # Jointure sur le relevé : le `default_scope` de soft-deletion s'applique,
    # donc les lignes d'un relevé supprimé ne bloquent rien. Le contrôleur les
    # détruit de toute façon — ceci est la ceinture, ça la bretelle.
    def already_reported_ids
      CarrierStatementLine.joins(:carrier_statement).select(:experience_booking_id)
    end
  end
end
