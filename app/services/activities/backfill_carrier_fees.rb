module Activities
  # Complète `carrier_fee_cents` sur les réservations DÉJÀ confirmées en base
  # (epic #244, phase 1). Le callback de `ExperienceBooking` ne fige le montant
  # qu'au moment de la confirmation : tout ce qui a été confirmé avant cette
  # phase est resté vide, dont la fiche activités 2026 qui n'a jamais été
  # traitée.
  #
  # Chaque montant est calculé au tarif EN VIGUEUR À LA DATE DU CRÉNEAU, pas au
  # tarif d'aujourd'hui — sinon la reprise réécrirait l'histoire.
  #
  #   bin/rails activities:backfill_carrier_fees          # dry-run
  #   bin/rails activities:backfill_carrier_fees APPLY=1  # écrit
  class BackfillCarrierFees
    Result = Struct.new(:filled, :without_duration, :total_cents, keyword_init: true) do
      def to_s
        "#{filled.size} réservation(s) complétée(s) pour " \
          "#{format('%.2f', total_cents / 100.0)} €, " \
          "#{without_duration.size} sans durée en heures"
      end
    end

    def initialize(dry_run: true)
      @dry_run = dry_run
    end

    def run
      result = Result.new(filled: [], without_duration: [], total_cents: 0)

      scope.find_each do |booking|
        fee = booking.computed_carrier_fee_cents

        if fee.nil?
          result.without_duration << describe(booking)
          next
        end

        booking.update_column(:carrier_fee_cents, fee) unless @dry_run
        result.filled << "#{describe(booking)} — #{format('%.2f', fee / 100.0)} €"
        result.total_cents += fee
      end

      result
    end

    private

    # `update_column` plutôt que `update!` : la reprise ne doit ni rejouer les
    # validations d'une réservation ancienne (un créneau depuis rempli refuserait
    # sa propre réservation), ni toucher `updated_at`.
    def scope
      ExperienceBooking.confirmed
                       .where(carrier_fee_cents: nil)
                       .includes(experience_availability: :experience)
    end

    def describe(booking)
      availability = booking.experience_availability
      "##{booking.id} #{availability&.experience&.name} du #{availability&.available_on}"
    end
  end
end
