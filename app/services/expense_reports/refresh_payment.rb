module ExpenseReports
  # Le paiement d'une note est un RAPPROCHEMENT (epic #241, décision 6), comme
  # celui d'une facture d'achat.
  #
  # On ne coche pas « payée » : on constate que les lignes de trésorerie
  # affectées sur le `440000` avec cette note en `document` couvrent son total.
  # Et ça marche dans les deux sens — défaire l'affectation la remet « à payer ».
  # Un état qui ne sait que monter est un état faux.
  #
  # Jumeau de `PurchaseInvoices::RefreshPayment` : même forme, mêmes garde-fous.
  # Les deux chemins vers `paid` (l'espèce et le virement) passent par le même
  # `after_update_commit` du modèle, donc par le même email au bénéficiaire.
  class RefreshPayment < ServiceBase
    def initialize(expense_report:)
      @report = expense_report
    end

    def run = catch_error(context: { expense_report: @report&.id }) { refresh }
    def run! = refresh

    private

    def refresh
      return @report if @report.blank?
      return @report unless %w[processing paid].include?(@report.status)

      total = @report.total_cents
      couvert = @report.cash_allocations.sum(:amount_cents).abs

      if total.positive? && couvert >= total
        return @report if @report.paid?

        @report.update!(status: "paid", paid_on: last_entry_date || Date.current)
      elsif @report.paid?
        # Retour en arrière : le statut redescend, mais on NE rejoue PAS l'email
        # (`paid_notified_at` reste posé). Le bénéficiaire a déjà été prévenu ;
        # lui envoyer un second « ta note a été payée » après un dérapprochement
        # serait au mieux troublant.
        @report.update!(status: "processing", paid_on: nil)
      end

      @report.reload
    end

    def last_entry_date
      @report.cash_allocations.includes(:cash_entry).filter_map { |a| a.cash_entry&.entry_date }.max
    end
  end
end
