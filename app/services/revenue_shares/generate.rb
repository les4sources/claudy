module RevenueShares
  # Construit le relevé BROUILLON d'une période (issue #247).
  #
  # Rien n'est figé ici : on pose les lignes retenues par `Selection` et on
  # calcule base et part. Le geste est réversible — un brouillon se supprime —
  # et c'est voulu : l'émission, elle, ne l'est pas.
  class Generate < ServiceBase
    class AlreadyReported < StandardError; end
    class NothingToReport < StandardError; end

    def initialize(agreement:, period_from:, period_to: nil, whodunnit: nil)
      @agreement = agreement
      @from = period_from.is_a?(String) ? Date.parse(period_from) : period_from.to_date
      @to = (period_to.presence && (period_to.is_a?(String) ? Date.parse(period_to) : period_to.to_date)) ||
            @agreement.period_end_for(@from)
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { agreement: @agreement.id, period_from: @from }) { generate }
    end

    def run! = generate

    private

    def generate
      statement = nil

      PaperTrail.request(whodunnit: @whodunnit || "revenue_share") do
        ApplicationRecord.transaction do
          @agreement.lock!
          raise AlreadyReported, "Un relevé existe déjà pour #{@agreement.period_label_for(@from)}." if existing

          selection = Selection.new(agreement: @agreement, period_from: @from, period_to: @to)
          if selection.retained.empty?
            raise NothingToReport,
                  "Aucune réservation à relever pour #{@agreement.period_label_for(@from)}."
          end

          statement = RevenueShareStatement.create!(
            revenue_share_agreement: @agreement,
            period_from: @from, period_to: @to, status: "draft",
            base_cents: selection.base_cents, share_cents: selection.share_cents
          )

          selection.retained.each do |line|
            statement.revenue_share_statement_lines.create!(
              booking: line.booking, kind: line.kind, origin_line: line.origin_line,
              from_date: line.booking.from_date, to_date: line.booking.to_date,
              label: line.label, amount_cents: line.amount_cents
            )
          end
        end
      end

      statement
    rescue ActiveRecord::RecordNotUnique
      # Deux générations vraiment concurrentes : l'index unique a tranché. On
      # rend celle qui a gagné plutôt que de lever — le résultat métier est bon.
      existing or raise
    end

    def existing
      RevenueShareStatement.find_by(revenue_share_agreement_id: @agreement.id, period_from: @from)
    end
  end
end
