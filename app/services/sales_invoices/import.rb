module SalesInvoices
  # Reprendre un lot de factures émises dans OkiOki (`/api/me/invoices`,
  # Michael 2026-10-30), pièce par pièce :
  #
  # - déjà au registre (même entité, même numéro) : ignorée, jamais doublée ;
  # - son écriture de vente est déjà au grand livre (reprise Winbooks, journal
  #   tenu à la main) : rattachée à elle (`AttachEntry`), sans nouvelle écriture ;
  # - sinon : enregistrée et passée au journal Ventes (`Record`), sauf en
  #   « rattacher seulement ».
  #
  # Chaque pièce dans son point de sauvegarde : un refus (total qui contredit
  # l'écriture, mois arrêté, client inconnu…) n'arrête pas les suivantes. Les
  # factures passent avant les notes de crédit, pour qu'une note retrouve la
  # facture qu'elle corrige dans le même lot.
  class Import < ServiceBase
    Outcome = Struct.new(:piece, :action, :invoice, :detail, :linked, keyword_init: true)

    ACTIONS = %w[existing attached recorded skipped refused].freeze

    REFUSALS = [
      AttachEntry::Refused, ActiveRecord::RecordInvalid, Unpost::Refused,
      Accounting::PostSalesInvoice::NotPostable, Accounting::PostSalesInvoice::MissingAccount,
      Accounting::PostDocument::MissingFiscalYear
    ].freeze

    # `pieces` : des hash
    #   { legal_entity:, number:, issued_on:, kind:, total_cents:, third_party:,
    #     third_party_error:, lines: [attributs de ligne], lines_error:,
    #     credited_number:, payment_reference:, notes:, error: }
    def initialize(pieces:, attach_only: false, whodunnit: nil)
      @pieces = pieces
      @attach_only = attach_only
      @whodunnit = whodunnit || "okioki-import"
    end

    def run = catch_error { import }
    def run! = import

    private

    def import
      ordonnees = @pieces.sort_by { |p| [p[:kind] == "credit_note" ? 1 : 0, p[:issued_on].to_s, p[:number].to_s] }
      PaperTrail.request(whodunnit: @whodunnit) do
        ordonnees.map { |piece| import_piece(piece) }
      end
    end

    def import_piece(piece)
      return outcome(piece, "refused", detail: piece[:error]) if piece[:error]

      existante = SalesInvoice.find_by(legal_entity: piece[:legal_entity], number: piece[:number])
      return outcome(piece, "existing", invoice: existante, detail: "déjà au registre (##{existante.id})") if existante

      ecritures = candidate_entries(piece)
      if ecritures.size > 1
        return outcome(piece, "refused", detail: "plusieurs écritures de vente répondent au numéro " \
                                                 "(#{ecritures.map(&:reference).join(', ')}) : rattache-la à la main.")
      end

      ApplicationRecord.transaction(requires_new: true) do
        ecritures.one? ? attach(piece, ecritures.first) : record(piece)
      end
    rescue *REFUSALS => e
      outcome(piece, "refused", detail: e.respond_to?(:record) ? e.record.errors.full_messages.to_sentence : e.message)
    end

    def attach(piece, entry)
      attributs = common_attributes(piece).merge("total_cents" => piece[:total_cents])
      # Le tiers de l'écriture fait foi : le nom du client OkiOki ne sert
      # que si l'écriture n'en porte pas.
      if entry_has_third_party?(entry)
        attributs.delete("third_party_id")
      elsif piece[:third_party].nil?
        raise AttachEntry::Refused, piece[:third_party_error] || "client inconnu, et #{entry.reference} n'en porte pas."
      end

      service = AttachEntry.new(journal_entry: entry, attributes: attributs, whodunnit: @whodunnit)
      service.run!
      outcome(piece, "attached", invoice: service.invoice, linked: service.linked_allocations,
                                 detail: ["rattachée à #{entry.reference}", *service.warnings].join(" · "))
    end

    def record(piece)
      return outcome(piece, "skipped", detail: "aucune écriture de vente à rattacher : pas passée (rattacher seulement).") if @attach_only
      raise AttachEntry::Refused, piece[:third_party_error] || "client inconnu." if piece[:third_party].nil?
      raise AttachEntry::Refused, piece[:lines_error] if piece[:lines_error]

      attributs = common_attributes(piece).merge(
        "legal_entity_id" => piece[:legal_entity].id, "total_cents" => piece[:total_cents],
        "sales_invoice_lines_attributes" => piece[:lines]
      )
      service = Record.new(attributes: attributs, whodunnit: @whodunnit)
      service.run!
      outcome(piece, "recorded", invoice: service.invoice, detail: "passée au journal Ventes (#{service.invoice.journal_entry&.reference})")
    end

    def common_attributes(piece)
      corrigee = SalesInvoice.find_by(legal_entity: piece[:legal_entity], number: piece[:credited_number]) if piece[:credited_number].present?
      {
        "number" => piece[:number], "issued_on" => piece[:issued_on], "kind" => piece[:kind],
        "third_party_id" => piece[:third_party]&.id, "credited_invoice_id" => corrigee&.id,
        "payment_reference" => piece[:payment_reference], "notes" => piece[:notes]
      }.compact
    end

    # Les écritures de vente qui portent ce numéro et n'ont pas encore de
    # facture : la référence de la pièce reprise, ou le libellé qui commence
    # par lui.
    def candidate_entries(piece)
      AttachEntry.entries_for(legal_entity: piece[:legal_entity], reference: piece[:number])
                 .where(reversal_of_id: nil)
                 .where.not(id: JournalEntry.where.not(reversal_of_id: nil).select(:reversal_of_id))
                 .where.not(id: SalesInvoice.where.not(journal_entry_id: nil).select(:journal_entry_id))
                 .where("journal_entries.source_type IS NULL OR journal_entries.source_type <> 'SalesInvoice'")
                 .to_a
    end

    def entry_has_third_party?(entry)
      entry.journal_lines.joins(:general_account)
           .where("general_accounts.code LIKE ?", "#{AttachEntry::CUSTOMER_PREFIX}%")
           .where.not(third_party_id: nil).exists?
    end

    def outcome(piece, action, invoice: nil, detail: nil, linked: [])
      Outcome.new(piece: piece, action: action, invoice: invoice, detail: detail, linked: linked)
    end
  end
end
