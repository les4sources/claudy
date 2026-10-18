module Finance
  # « À faire » (Michael, 2026-10-17) : les files de la comptabilité, dans
  # l'ordre du travail, avec ce qui attend dans chacune.
  #
  # Une personne qui démarre ouvre la Vue d'ensemble et ne sait pas par où
  # commencer : dix-neuf écrans, chacun juste, aucun qui dise « commence ici ».
  # Cette liste le dit. Elle ne stocke rien et ne coche rien : chaque ligne
  # interroge la base, comme l'arrêté du mois, et repasse à faire toute seule
  # quand une file se remplit.
  #
  # L'ordre est celui du circuit de l'argent : ce qui ENTRE (mails, relevés),
  # puis ce qu'on EXPLIQUE (affecter, compléter, traiter), puis ce qu'on PAIE,
  # puis ce qu'on FERME. Une file qui attend quelqu'un d'autre (la validation
  # d'un pôle) est montrée, mais n'est pas à faire.
  class AccountingTodo
    Item = Data.define(:label, :detail, :count, :state, :path) do
      def todo? = state == :todo
      def waiting? = state == :waiting
      def done? = state == :done
    end

    # Au-delà d'une semaine sans relevé, les lignes s'accumulent et on ne se
    # souvient plus de ce qu'elles paient.
    STALE_IMPORT_DAYS = 7

    def initialize(today: Date.current)
      @today = today
    end

    def items
      @items ||= [inbox, bank_import, unallocated, invoices_to_complete, invoices_to_validate,
                  expense_reports, carrier_statements, payables, monthly_close].compact
    end

    def todo_count = items.count(&:todo?)

    private

    include Rails.application.routes.url_helpers
    include ActionView::Helpers::NumberHelper

    def inbox
      n = MailMessage.pending.count
      Item.new(label: "Classer les mails reçus",
               detail: n.zero? ? "La boite de réception est vide." : "#{n} mail(s) à transformer en facture ou à ignorer.",
               count: n, state: n.zero? ? :done : :todo, path: finance_mail_messages_path)
    end

    def bank_import
      last = CodaImport.maximum(:created_at)&.to_date
      days = last && (@today - last).to_i
      stale = days.nil? || days > STALE_IMPORT_DAYS
      detail = if last.nil?
                 "Aucun relevé n'a encore été importé."
               else
                 "Dernier relevé importé il y a #{days} jour(s)#{stale ? ' : télécharge le suivant à la banque.' : '.'}"
               end
      Item.new(label: "Importer les relevés bancaires", detail: detail, count: nil,
               state: stale ? :todo : :done, path: finance_coda_imports_path)
    end

    def unallocated
      lines = CashEntry.pending
      n = lines.count
      detail = n.zero? ? "Toutes les lignes sont expliquées." : "#{n} ligne(s), #{euros(lines.sum(Arel.sql('ABS(cash_entries.amount_cents)')))} de mouvements : à rapprocher ou à affecter."
      Item.new(label: "Affecter les mouvements", detail: detail, count: n,
               state: n.zero? ? :done : :todo, path: finance_unallocated_cash_entries_path)
    end

    def invoices_to_complete
      n = PurchaseInvoice.with_status("to_process").count
      Item.new(label: "Compléter les factures d'achat",
               detail: n.zero? ? "Aucune facture à compléter." : "#{n} facture(s) dont les lignes ne couvrent pas encore le total.",
               count: n, state: n.zero? ? :done : :todo,
               path: finance_purchase_invoices_path(status: "to_process"))
    end

    # Pas un geste de la comptabilité : c'est le pôle qui doit dire oui. On le
    # montre pour qu'on sache relancer, sans l'ajouter au compte « à faire ».
    def invoices_to_validate
      n = PurchaseInvoice.with_status("to_validate").count
      return if n.zero?

      Item.new(label: "Factures en attente d'un pôle",
               detail: "#{n} facture(s) attendent la validation d'un pôle. Relance si ça traîne.",
               count: n, state: :waiting, path: finance_purchase_invoices_path(status: "to_validate"))
    end

    def expense_reports
      n = ExpenseReport.with_status("recorded").count
      Item.new(label: "Traiter les notes de frais",
               detail: n.zero? ? "Aucune note en attente." : "#{n} note(s) encodée(s), à passer en traitement.",
               count: n, state: n.zero? ? :done : :todo,
               path: finance_expense_reports_path(status: "recorded"))
    end

    def carrier_statements
      n = CarrierStatement.draft.count
      return if n.zero?

      Item.new(label: "Émettre les relevés des porteurs",
               detail: "#{n} relevé(s) en brouillon, à relire puis émettre.",
               count: n, state: :todo, path: finance_carrier_statements_path)
    end

    def payables
      rows = Finance::PayableQueue.new.rows
      n = rows.size
      detail = n.zero? ? "Rien n'attend de virement." : "#{n} dette(s) pour #{euros(rows.sum(&:remaining_cents))} attendent leur virement."
      Item.new(label: "Faire les virements", detail: detail, count: n,
               state: n.zero? ? :done : :todo, path: finance_payables_path)
    end

    def monthly_close
      month = @today.prev_month.beginning_of_month
      closed = MonthClosing.closed?(month)
      name = I18n.l(month, format: "%B %Y")
      Item.new(label: "Arrêter le mois précédent",
               detail: closed ? "#{name.capitalize} est arrêté." : "#{name.capitalize} n'est pas encore arrêté.",
               count: nil, state: closed ? :done : :todo,
               path: finance_monthly_close_path(month: month.strftime("%Y-%m")))
    end

    def euros(cents) = number_to_currency(cents / 100.0, unit: "€", precision: 0)
  end
end
