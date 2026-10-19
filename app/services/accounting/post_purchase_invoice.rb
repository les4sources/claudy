module Accounting
  # Comptabilise une facture d'achat au passage en « À payer » (epic #240,
  # décision 3).
  #
  # Débit des comptes de charge portés par les lignes — avec leur pôle et leur
  # analytique, c'est là que se joue la lecture par pôle — crédit du `440000`
  # avec le tiers. Le tiers est sur la LIGNE et non sur l'écriture : c'est cette
  # ligne 440000 qu'on lettrera contre son paiement.
  #
  # La TVA des lignes (epic #240, 2026-10-19) : pour une entité assujettie qui a
  # ouvert le `411000`, elle part en TVA à récupérer et la charge reste HTVA.
  # Sinon (fondation exemptée, franchise, ou 411000 encore désactivé) la TVA
  # ne se récupère pas : elle fait partie de la charge, TVAC.
  #
  # Idempotent : `PostDocument` rend l'écriture existante si le même document a
  # déjà été passé dans le même journal.
  class PostPurchaseInvoice < ServiceBase
    class NotBalanced < StandardError; end
    class MissingSupplierAccount < StandardError; end

    SUPPLIER_CODE = "440000".freeze
    VAT_RECOVERABLE_CODE = "411000".freeze

    def initialize(purchase_invoice:, whodunnit: nil)
      @invoice = purchase_invoice
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { purchase_invoice: @invoice&.id }) { post }
    def run! = post

    private

    def post
      lines = @invoice.purchase_invoice_lines.includes(:general_account, :team, :analytic_account).to_a
      raise NotBalanced, "Cette facture n'a aucune ligne de ventilation." if lines.empty?

      total = lines.sum(&:amount_cents)
      if total != @invoice.total_cents
        raise NotBalanced,
              "Les lignes portent #{Money.new(total, 'EUR').format} pour un total de " \
              "#{Money.new(@invoice.total_cents, 'EUR').format} — la ventilation doit couvrir la facture."
      end

      entry = PostDocument.new(
        legal_entity: @invoice.legal_entity,
        journal: "purchases",
        entry_date: @invoice.issued_on,
        label: [@invoice.third_party.name, @invoice.number].compact_blank.join(" · "),
        source: @invoice,
        whodunnit: @whodunnit,
        lines: charge_lines(lines) + vat_lines(lines) + [supplier_line]
      ).run!

      @invoice.update_column(:posted_at, Time.current) if @invoice.posted_at.blank?
      entry
    end

    def charge_lines(lines)
      lines.map do |line|
        {
          account: line.general_account,
          team: line.team,
          analytic_account: line.analytic_account,
          label: line.display_label,
          debit_cents: recoverable_vat_account ? line.net_amount_cents : line.amount_cents
        }
      end
    end

    def vat_lines(lines)
      vat = lines.sum(&:vat_cents)
      return [] if recoverable_vat_account.nil? || vat.zero?

      [{ account: recoverable_vat_account, label: "TVA à récupérer", debit_cents: vat }]
    end

    def recoverable_vat_account
      return @recoverable_vat_account if defined?(@recoverable_vat_account)

      @recoverable_vat_account =
        (GeneralAccount.find_by(code: VAT_RECOVERABLE_CODE, active: true) if @invoice.legal_entity.vat_regime == "subject")
    end

    def supplier_line
      {
        account: supplier_account,
        third_party: @invoice.third_party,
        label: @invoice.third_party.name,
        credit_cents: @invoice.total_cents
      }
    end

    def supplier_account
      @supplier_account ||= GeneralAccount.find_by(code: SUPPLIER_CODE) ||
                            raise(MissingSupplierAccount,
                                  "Le compte fournisseurs #{SUPPLIER_CODE} n'existe pas — " \
                                  "lance `rake accounting:seed_reference`.")
    end
  end
end
