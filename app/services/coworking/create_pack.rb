module Coworking
  # Achat d'un pack de coworking par l'équipe, pour un client existant
  # (epic #126, Phase 1).
  #
  # Le prix vient du barème (`Pricing::Catalog.coworking_pack_cents`), jamais du
  # formulaire. Virement et espèces créent immédiatement un `Payment` en attente
  # ancré sur le pack — c'est ce paiement qui porte le statut, pas le pack.
  class CreatePack
    attr_reader :pack, :error_message

    def run(customer_id:, days_total:, payment_method:)
      @pack = CoworkingPack.new(
        customer_id: customer_id,
        days_total: days_total.to_i,
        payment_method: payment_method.to_s
      )

      ActiveRecord::Base.transaction do
        @pack.save!
        create_pending_payment! if @pack.deferred_payment?
      end

      true
    rescue ActiveRecord::RecordInvalid => e
      @error_message = e.record.errors.full_messages.to_sentence
      false
    end

    private

    def create_pending_payment!
      Payment.create!(
        coworking_pack: @pack,
        amount_cents: @pack.price_cents,
        payment_method: @pack.payment_method,
        status: "pending"
      )
    end
  end
end
