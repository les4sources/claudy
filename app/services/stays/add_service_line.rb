module Stays
  # Ajoute un service annexe à un séjour (Michael, 2026-10-23) : le prêt d'un
  # set de disc-golf, et ce qui viendra.
  #
  # Le libellé et le montant sont ceux qu'on a saisis. Un service du catalogue
  # (/services) les préremplit quand ils manquent : sans libellé, son nom ;
  # sans montant, son prix. La ligne garde aussi son compte de recette.
  #
  # Le total du séjour et son statut de paiement sont recalculés.
  class AddServiceLine < ServiceBase
    attr_reader :stay, :line

    def initialize(stay:)
      @stay = stay
    end

    def run(label:, amount_cents:, service: nil)
      catch_error(context: { stay_id: stay.id }) { run!(label: label, amount_cents: amount_cents, service: service) }
    end

    def run!(label:, amount_cents:, service: nil)
      label = label.to_s.strip.presence || service&.name
      amount_cents = service&.price_cents if amount_cents.nil?
      raise ServiceError, "Indique un libellé, ou choisis un service." if label.blank?
      raise ServiceError, "Indique un montant." if amount_cents.nil?
      raise ServiceError, "Le montant ne peut pas être négatif." if amount_cents.negative?

      ApplicationRecord.transaction do
        @line = stay.service_lines.create!(label: label, amount_cents: amount_cents, service: service)
        stay.recompute_aggregates!
        stay.set_payment_status
      end
      @line
    end

    # « 12,50 », « 12.5 », « 12 » → 1250. Vide → nil (le prix du service).
    def self.cents_from(raw)
      value = raw.to_s.strip.delete(" €").tr(",", ".")
      return nil if value.empty?

      (BigDecimal(value) * 100).round.to_i
    rescue ArgumentError
      raise ServiceError, "Montant illisible : « #{raw} »."
    end
  end
end
