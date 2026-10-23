module Finance
  # Le virement qui paie un relevé de dépôt-vente en mode virement (epic #248,
  # phase 3).
  #
  # `Consignments::Settle` passe la dette (600000 / 440000 au tiers de
  # l'artisan) et met le relevé dans « À payer » ; c'est ce rapprochement qui
  # le solde. Affecter la ligne bancaire sortante sur le `440000` avec le
  # RELEVÉ en `document`, le tiers de l'écriture du relevé et son entité : la
  # dette se lettre, et le `after_commit` de `CashAllocation` fait passer le
  # relevé `settled` (`Consignments::RefreshSettlement`) quand il est couvert.
  #
  # Jumeau de `Finance::RecordCarrierStatementPayment`.
  class RecordConsignmentReportPayment < ServiceBase
    class NotPayable < StandardError; end
    class WrongDirection < StandardError; end
    class TooMuch < StandardError; end
    class MissingAccount < StandardError; end

    SUPPLIER_CODE = "440000".freeze

    def initialize(consignment_report:, cash_entry:, amount_cents: nil, whodunnit: nil)
      @report = consignment_report
      @entry = cash_entry
      @amount_cents = amount_cents&.to_i&.abs
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { consignment_report: @report&.id }) { record }
    def run! = record

    private

    def record
      raise NotPayable, "Aucun relevé de dépôt-vente à payer." if @report.blank?
      unless @report.consignor&.paid_by_transfer?
        raise NotPayable,
              "#{@report.consignor&.name} facture ses ventes : c'est sa facture d'achat qui se paie, pas le relevé."
      end
      raise NotPayable, "Ce relevé est #{@report.status_label.downcase} : seul un relevé vérifié se paie." unless @report.verified?
      raise NotPayable, "Ce relevé n'est pas encore réglé : clique d'abord « Régler » sur sa fiche." unless @report.posted?
      raise WrongDirection, "Un relevé se paie depuis une ligne SORTANTE." unless @entry.amount_cents.negative?

      du = @report.remaining_cents
      raise NotPayable, "Ce relevé est déjà entièrement rapproché." unless du.positive?

      # Sans montant explicite on solde ce qui reste, dans la limite de ce que la
      # ligne peut encore porter.
      montant = @amount_cents || [du, @entry.remaining_cents.abs].min
      if montant > du
        raise TooMuch,
              "Ce relevé n'attend que #{Money.new(du, 'EUR').format} — " \
              "en affecter #{Money.new(montant, 'EUR').format} le surpaierait."
      end

      PaperTrail.request(whodunnit: @whodunnit || "consignment_report_payment") do
        ApplicationRecord.transaction do
          @entry.lock!

          @entry.cash_allocations.create!(
            general_account: supplier_account,
            legal_entity: legal_entity,
            third_party: third_party,
            document: @report,
            amount_cents: -montant,
            label: "Paiement #{@report.payable_label} — #{@report.reference}"
          )

          Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: @whodunnit).run! if @entry.reload.fully_allocated?
        end
      end

      @report.reload
    end

    def journal_entry = @report.journal_entry

    # L'entité qui porte la dette : celle de l'écriture du relevé. Payée depuis
    # la banque d'une autre entité, `PostCashEntry` passe par le compte courant
    # inter-entités.
    def legal_entity
      journal_entry&.legal_entity || @report.legal_entity || @entry.cash_account.legal_entity
    end

    # Le tiers de la ligne 440000 de l'écriture du relevé : c'est lui qu'on
    # lettre. `PostConsignmentReport` peut l'avoir créé au nom de l'artisan sans
    # le rattacher au contrat.
    def third_party
      ligne = journal_entry&.journal_lines&.find { |l| l.general_account_id == supplier_account.id && l.credit_cents.to_i.positive? }
      ligne&.third_party || @report.payable_third_party
    end

    def supplier_account
      @supplier_account ||= GeneralAccount.find_by(code: SUPPLIER_CODE) ||
                            raise(MissingAccount,
                                  "Le compte des dettes fournisseurs #{SUPPLIER_CODE} n'existe pas — " \
                                  "lance `rake accounting:seed_reference`.")
    end
  end
end
