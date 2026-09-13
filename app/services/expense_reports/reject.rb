module ExpenseReports
  # Le refus d'une note (epic #241, phase 1).
  #
  # Une note rejetée ne disparaît pas et ne se vide pas : elle garde ses lignes
  # et gagne un motif. C'est ce motif qui permettra d'en discuter avec son
  # auteur (epic #242) plutôt que de lui rendre une feuille sans explication.
  class Reject < ServiceBase
    class BadStatus < StandardError; end
    class MissingReason < StandardError; end

    def initialize(expense_report:, reason:, whodunnit: nil)
      @report = expense_report
      @reason = reason.to_s.strip
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { expense_report: @report.id }) { reject }
    end

    def run! = reject

    private

    def reject
      raise MissingReason, "Dis pourquoi la note est rejetée — sinon personne ne peut la corriger." if @reason.blank?
      unless @report.recorded?
        raise BadStatus,
              "Une note #{@report.status_label.downcase} ne se rejette plus — " \
              "sa pièce comptable existe, il faut la contre-passer."
      end

      PaperTrail.request(whodunnit: @whodunnit || "expense_reports") do
        @report.update!(status: "rejected", rejection_reason: @reason)
      end

      @report
    end
  end
end
