module PurchaseInvoices
  # « Payée en caisse » (epic #240, phase 4).
  #
  # Le fournisseur du marché repart avec ses 120 € en billets. Ça ne se note pas
  # « payée » à la main : ça crée une vraie sortie de caisse, affectée sur le
  # `440000` avec la facture en document. Sans quoi la dette resterait au grand
  # livre alors que l'argent est parti, et la caisse serait fausse d'autant.
  #
  # Même patron que `ExpenseReports::PayInCash` — c'est le même geste sur une
  # autre dette, il n'a aucune raison de se comporter autrement.
  class PayInCash < ServiceBase
    class BadStatus < StandardError; end
    class NoCashAccount < StandardError; end
    class MonthClosed < StandardError; end
    class MissingAccount < StandardError; end

    SUPPLIER_CODE = "440000".freeze

    def initialize(purchase_invoice:, paid_on: nil, cash_account: nil, whodunnit: nil)
      @invoice = purchase_invoice
      @paid_on = paid_on.presence
      @cash_account = cash_account
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { purchase_invoice: @invoice&.id }) { pay }
    def run! = pay

    private

    def pay
      unless @invoice.to_pay?
        raise BadStatus,
              "Seule une facture « À payer » se règle en espèces — celle-ci est " \
              "#{@invoice.status_label.downcase}."
      end

      montant = @invoice.remaining_cents
      raise BadStatus, "Cette facture est déjà entièrement rapprochée." unless montant.positive?

      account = @cash_account || default_cash_account
      if account.blank?
        raise NoCashAccount,
              "Aucune caisse active pour #{@invoice.legal_entity.name} — " \
              "crée-la dans Comptabilité > Vue d'ensemble avant de payer en espèces."
      end

      date = parsed_date
      if MonthClosing.closed?(date)
        raise MonthClosed,
              "#{I18n.l(date.beginning_of_month, format: '%B %Y')} est arrêté — " \
              "une sortie de caisse ne s'y ajoute plus."
      end

      PaperTrail.request(whodunnit: @whodunnit || "purchase_invoices") do
        ApplicationRecord.transaction do
          entry = CashEntry.create!(
            cash_account: account, entry_date: date, amount_cents: -montant,
            label: "Paiement #{@invoice.payable_label}"
          )
          entry.cash_allocations.create!(
            general_account: supplier_account,
            legal_entity: @invoice.legal_entity,
            third_party: @invoice.third_party,
            document: @invoice,
            amount_cents: -montant,
            label: entry.label
          )
          Accounting::PostCashEntry.new(cash_entry: entry, whodunnit: @whodunnit).run!
          entry
        end
      end

      @invoice.reload
    end

    def default_cash_account
      CashAccount.actives.where(kind: "cash", legal_entity_id: @invoice.legal_entity_id).ordered.first
    end

    def supplier_account
      GeneralAccount.find_by(code: SUPPLIER_CODE) ||
        raise(MissingAccount,
              "Le compte #{SUPPLIER_CODE} n'existe pas — lance `rake accounting:seed_reference`.")
    end

    def parsed_date
      return Date.current if @paid_on.blank?

      @paid_on.is_a?(String) ? Date.parse(@paid_on) : @paid_on
    end
  end
end
