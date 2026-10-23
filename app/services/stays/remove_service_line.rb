module Stays
  # Retire un service annexe du séjour (suppression douce, PaperTrail garde la
  # trace), puis recalcule le total et le statut de paiement.
  class RemoveServiceLine < ServiceBase
    def initialize(line:)
      @line = line
    end

    def run
      catch_error(context: { stay_service_line_id: @line.id }) { run! }
    end

    def run!
      stay = @line.stay
      ApplicationRecord.transaction do
        @line.soft_delete!
        stay.recompute_aggregates!
        stay.set_payment_status
      end
      true
    end
  end
end
