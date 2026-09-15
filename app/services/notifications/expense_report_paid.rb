module Notifications
  # « Ta note de frais a été payée » (epic #242, phase 3).
  #
  # Au bénéficiaire, et à lui seul : la comptabilité sait déjà qu'elle vient de
  # payer. C'est la notification qui ferme la boucle d'une note — sans elle, le
  # bénéficiaire ne sait pas que l'argent est parti, et il relance.
  #
  # Passe par `Notify`, seul point de création : la ligne, l'email si la personne
  # le veut, et la trace de l'envoi partent ensemble.
  class ExpenseReportPaid
    def initialize(report)
      @report = report
    end

    def self.call(report) = new(report).call

    def call
      recipient = @report.human&.user
      return nil if recipient.blank?

      Notify.new(
        recipient: recipient,
        kind: "expense_report_paid",
        title: title,
        body: body,
        url: @report.comment_path,
        notifiable: @report
      ).tap(&:run).notification
    end

    private

    def title
      montant = Money.new(@report.total_cents, "EUR").format
      "#{@report.kind_label} #{@report.reference.presence || "##{@report.id}"} payée — #{montant}"
    end

    def body
      return "Le paiement est enregistré." if @report.paid_on.blank?

      "Payée le #{I18n.l(@report.paid_on, format: :long)}."
    end
  end
end
