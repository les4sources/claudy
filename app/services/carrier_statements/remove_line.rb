module CarrierStatements
  # Retirer une prestation d'un relevé en BROUILLON (Michael, 2026-11-12).
  #
  # Deux sens, et le porteur ne les vit pas pareil :
  # - « Reporter » : la prestation quitte ce relevé et revient au suivant
  #   (tenue hors période, ou à vérifier avant de la payer) ;
  # - « Ne pas payer » : sa rémunération passe à 0 €, elle ne revient plus
  #   (deux séjours sur un même créneau, une prestation offerte). La sélection
  #   ignore les prestations à 0 €.
  #
  # La ligne part pour de bon, pas en soft-delete : l'index unique sur
  # `experience_booking_id` interdirait sinon de jamais la relever à nouveau.
  class RemoveLine < ServiceBase
    class Refused < StandardError; end

    attr_reader :statement

    def initialize(line:, pay: true, whodunnit: nil)
      @line = line
      @statement = line.carrier_statement
      @pay = pay
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { carrier_statement_line: @line&.id }) { remove }
    def run! = remove

    private

    def remove
      raise Refused, "Ce relevé est #{@statement.status_label.downcase} : rouvre-le en brouillon pour le corriger." unless @statement.draft?

      booking = @line.experience_booking
      PaperTrail.request(whodunnit: @whodunnit || "carrier_statement") do
        ApplicationRecord.transaction do
          @statement.lock!
          @line.destroy!
          booking.reload.update!(carrier_fee_cents: 0) unless @pay
          @statement.recompute_total
          @statement.save!
        end
      end
      @statement
    end
  end
end
