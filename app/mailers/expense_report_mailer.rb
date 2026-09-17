# L'email au bénéficiaire d'une note de frais (epic #241, phase 3).
#
# Il ne part que dans un sens, et une seule fois : vers la personne qui a avancé
# l'argent, quand il lui revient. Sans lui, elle ne sait pas que le virement est
# parti — et elle relance la comptabilité, qui a déjà payé.
#
# Ce n'est pas un email client : il ne passe donc pas par `SentEmail`, réservé
# au journal des envois aux clients.
class ExpenseReportMailer < ApplicationMailer
  def paid(report)
    @report = report
    @lines  = report.expense_lines.includes(:general_account, :team)
    @admin_url = finance_expense_report_url(report, host: ENV.fetch("APPLICATION_HOST", "app.les4sources.be"))

    montant = Money.new(report.total_cents, "EUR").format
    mail(to: report.human&.email,
         subject: "Ta #{report.kind_label.downcase} #{report.payable_reference} a été payée — #{montant}")
  end
end
