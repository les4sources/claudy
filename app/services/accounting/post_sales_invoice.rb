module Accounting
  # Comptabilise une facture de vente sans réservation au journal Ventes
  # (Michael, 2026-10-30).
  #
  # Débit du `400000` avec le tiers — c'est cette ligne que les encaissements
  # viendront solder — crédit des comptes de produit des lignes, avec leur pôle
  # et leur analytique. Pour une entité assujettie, le produit est HTVA et la
  # TVA part en `451000` ; une entité exemptée (la fondation) n'a pas de TVA :
  # tout part au produit.
  #
  # Une note de crédit passe l'écriture inverse : crédit du 400000, débit des
  # produits et de la TVA.
  #
  # Les factures d'un séjour (`on_payment`) ne passent JAMAIS par ici : leur
  # recette arrive par la ventilation du séjour à l'encaissement.
  #
  # Idempotent : `PostDocument` rend l'écriture existante si la facture a déjà
  # été passée dans le journal Ventes.
  class PostSalesInvoice < ServiceBase
    class NotPostable < StandardError; end
    class MissingAccount < StandardError; end

    CUSTOMER_CODE = "400000".freeze
    VAT_DUE_CODE = "451000".freeze

    def initialize(sales_invoice:, whodunnit: nil)
      @invoice = sales_invoice
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { sales_invoice: @invoice&.id }) { post }
    def run! = post

    private

    def post
      raise NotPostable, "La facture #{@invoice.number} se comptabilise à l'encaissement du séjour." unless @invoice.on_issue?
      raise NotPostable, "La facture #{@invoice.number} n'a pas de tiers client." if @invoice.third_party.blank?

      lines = @invoice.sales_invoice_lines.includes(:general_account, :team, :analytic_account).to_a
      raise NotPostable, "La facture #{@invoice.number} n'a aucune ligne." if lines.empty?

      total = lines.sum(&:amount_cents)
      if total != @invoice.total_cents
        raise NotPostable,
              "Les lignes portent #{Money.new(total, 'EUR').format} pour un total de " \
              "#{Money.new(@invoice.total_cents, 'EUR').format}."
      end
      if MonthClosing.closed?(@invoice.issued_on)
        raise NotPostable,
              "#{I18n.l(@invoice.issued_on.beginning_of_month, format: '%B %Y')} est arrêté : " \
              "rouvre le mois avant d'y enregistrer une facture."
      end

      entry = PostDocument.new(
        legal_entity: @invoice.legal_entity,
        journal: "sales",
        entry_date: @invoice.issued_on,
        label: [(@invoice.credit_note? ? "Note de crédit" : nil), @invoice.number, @invoice.third_party.name].compact.join(" · "),
        source: @invoice,
        whodunnit: @whodunnit,
        lines: oriented(revenue_lines(lines) + vat_lines(lines) + [customer_line])
      ).run!

      @invoice.update_columns(posted_at: Time.current, journal_entry_id: entry.id)
      entry
    end

    # Les lignes sont écrites dans le sens d'une facture ; une note de crédit
    # les retourne toutes.
    # Une ligne négative (une remise) passe de l'autre côté : une ligne
    # d'écriture n'a jamais de montant négatif.
    def oriented(lines)
      lines.map do |line|
        debit = line[:debit_cents].to_i
        credit = line[:credit_cents].to_i
        debit, credit = credit, debit if @invoice.credit_note?
        debit, credit = -credit, 0 if credit.negative?
        debit, credit = 0, -debit if debit.negative?
        line.merge(debit_cents: debit, credit_cents: credit)
      end
    end

    def revenue_lines(lines)
      lines.map do |line|
        {
          account: line.general_account,
          team: line.team,
          analytic_account: line.analytic_account,
          label: line.display_label,
          credit_cents: @invoice.vat_subject? ? line.net_amount_cents : line.amount_cents
        }
      end
    end

    def vat_lines(lines)
      vat = lines.sum(&:vat_cents)
      return [] if !@invoice.vat_subject? || vat.zero?

      [{ account: account!(VAT_DUE_CODE, active: true), label: "TVA à payer", credit_cents: vat }]
    end

    def customer_line
      {
        account: account!(CUSTOMER_CODE),
        third_party: @invoice.third_party,
        label: @invoice.third_party.name,
        debit_cents: @invoice.total_cents
      }
    end

    def account!(code, active: false)
      scope = GeneralAccount.where(code: code)
      scope = scope.where(active: true) if active
      scope.first || raise(MissingAccount, "Le compte #{code} n'existe pas ou est désactivé — active-le dans le plan comptable.")
    end
  end
end
