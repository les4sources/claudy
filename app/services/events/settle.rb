module Events
  # « Régler l'événement » (epic #245, phase 3) : fige le partage, crée une part
  # par organisateur, et passe l'écriture.
  #
  # À partir de là l'événement est FERMÉ côté frais et recettes : ce qui a été
  # viré ne se recalcule plus. Une correction passe par une contre-passation,
  # pas par une nouvelle allocation qui déplacerait un chiffre déjà payé.
  class Settle < ServiceBase
    ALREADY_SETTLED = "Cet événement est déjà réglé.".freeze
    NOTHING_TO_SHARE = "Cet événement n'a aucun organisateur : il n'y a rien à répartir.".freeze
    NO_SHARE = "La part des organisateurs est nulle : il n'y a rien à régler.".freeze

    attr_reader :event, :settlement

    def initialize(event:, whodunnit: nil)
      @event = event
      @whodunnit = whodunnit
      @report_errors = false
    end

    def run = catch_error(context: { event_id: event.id }) { run! }

    def run!
      raise ServiceError, ALREADY_SETTLED if event.event_settlement.present?

      calculation = ShareCalculation.new(event)
      raise ServiceError, NOTHING_TO_SHARE if calculation.lines.empty?
      raise ServiceError, NO_SHARE unless calculation.organizers_cents.positive?

      EventSettlement.transaction do
        @settlement = EventSettlement.create!(
          event: event,
          revenue_cents: calculation.revenue_cents,
          costs_cents: calculation.costs_cents,
          base_cents: calculation.base_cents,
          organizer_share_percent: calculation.share_percent,
          organizers_cents: calculation.organizers_cents,
          house_cents: calculation.house_cents,
          status: "issued",
          issued_at: Time.current
        )

        calculation.lines.each do |line|
          @settlement.event_settlement_lines.create!(
            human: line.human, weight: line.weight, amount_cents: line.amount_cents
          )
        end

        Accounting::PostEventSettlement.new(event_settlement: @settlement, whodunnit: @whodunnit).run!
      end

      true
    end
  end
end
