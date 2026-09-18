module CarrierStatements
  # Génère un relevé en BROUILLON pour un porteur et une période (epic #244,
  # phase 3). Générer n'engage rien : c'est une proposition qu'on relit avant
  # d'émettre. Par défaut, le trimestre civil précédent — la cadence que l'epic
  # a retenue.
  class Generate < ServiceBase
    class NothingToReport < StandardError; end
    class AlreadyDrafted < StandardError; end

    attr_reader :statement

    def self.default_period(today = Date.current)
      quarter_start = Date.new(today.year, ((today.month - 1) / 3) * 3 + 1, 1)
      previous = quarter_start - 1.day
      [previous.beginning_of_quarter, previous.end_of_quarter]
    end

    def initialize(human:, period_from: nil, period_to: nil, whodunnit: nil)
      @human = human
      default_from, default_to = self.class.default_period
      @period_from = period_from || default_from
      @period_to = period_to || default_to
      @whodunnit = whodunnit
      @report_errors = false
    end

    def run = catch_error(context: { human_id: @human.id }) { run! }

    def run!
      existing = CarrierStatement.draft.find_by(human: @human)
      raise AlreadyDrafted, "Ce porteur a déjà un relevé en brouillon : relis-le ou supprime-le." if existing

      selection = Selection.new(human: @human, period_from: @period_from, period_to: @period_to)
      raise NothingToReport, "Aucune prestation tenue à relever sur cette période." unless selection.any?

      PaperTrail.request(whodunnit: @whodunnit || "carrier_statement") do
        CarrierStatement.transaction do
          @statement = CarrierStatement.create!(
            human: @human, period_from: @period_from, period_to: @period_to, status: "draft"
          )

          selection.bookings.each do |booking|
            @statement.carrier_statement_lines.create!(
              experience_booking: booking,
              fee_cents: booking.carrier_fee_cents.to_i,
              label: booking.experience&.name,
              occurred_on: booking.experience_availability&.available_on
            )
          end

          @statement.recompute_total
          @statement.save!
        end
      end

      @statement
    end
  end
end
