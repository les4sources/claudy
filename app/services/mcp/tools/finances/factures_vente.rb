module Mcp
  module Tools
    module Finances
      # Comptabilité > Clients > Ventes (SalesInvoicesController #index et
      # #show), et la file Facturation : ce qui attend sa facture.
      class FacturesVente < Base
        include Commun

        STATUTS = { "emises" => "issued", "payees" => "paid" }.freeze
        LIMITE = 60
        TYPES = { "stay" => "sejour", "booking" => "hebergement", "space_booking" => "espaces" }.freeze
        TYPES_FACTURE = { "facture" => "invoice", "note_de_credit" => "credit_note" }.freeze

        tool "factures_vente",
             title: "Factures de vente",
             description: "Le registre des factures émises (dans OkiOki) : numéro, date, client (tiers), montant, reste dû, " \
                          "payée ou non, ce qu'elles facturent ou leur écriture de vente, avec le total facturé (notes de " \
                          "crédit déduites) et le reste impayé du filtre. Filtres : tiers, impayees, type (facture, " \
                          "note_de_credit), entité, dates, numéro. `a_facturer` : la " \
                          "file Facturation, les réservations dont la facture est demandée (type et #id à passer à " \
                          "facture_vente). Avec `facture` : le détail, dont les lignes bancaires qui l'ont payée.",
             schema: {
               properties: {
                 a_facturer: { type: "boolean", description: "Montrer la file « factures à fournir »." },
                 facture: { type: %w[integer string], description: "Une facture (#id ou numéro) pour en voir le détail." },
                 statut: { type: "string", enum: STATUTS.keys },
                 impayees: { type: "boolean", description: "Seulement les factures dont il reste quelque chose à encaisser." },
                 type: { type: "string", enum: TYPES_FACTURE.keys, description: "Facture ou note de crédit." },
                 tiers: { type: "string", description: "Le tiers client (nom ou #id)." },
                 entite: ENTITE,
                 du: DATE, au: DATE,
                 recherche: { type: "string", description: "Numéro de facture." }
               }
             }

        def call(arguments)
          return detail(facture_vente!(arguments["facture"])) if arguments["facture"].present?
          return a_facturer if arguments["a_facturer"]

          scope = SalesInvoice.all
          if arguments["statut"].present?
            scope = scope.where(status: STATUTS[arguments["statut"]] || raise(Base::Error, "statut : #{STATUTS.keys.join(', ')}."))
          end
          scope = scope.where(legal_entity_id: entite!(arguments["entite"]).id) if arguments["entite"].present?
          scope = scope.where(third_party_id: tiers!(arguments["tiers"]).id) if arguments["tiers"].present?
          if arguments["type"].present?
            scope = scope.where(kind: TYPES_FACTURE[arguments["type"]] || raise(Base::Error, "type : #{TYPES_FACTURE.keys.join(', ')}."))
          end
          scope = scope.invoices.issued if arguments["impayees"]
          scope = scope.where(issued_on: date!(arguments["du"], "du")..) if arguments["du"].present?
          scope = scope.where(issued_on: ..date!(arguments["au"], "au")) if arguments["au"].present?
          scope = scope.where("sales_invoices.number ILIKE ?", "%#{SalesInvoice.sanitize_sql_like(arguments['recherche'])}%") if arguments["recherche"].present?

          factures = scope.ordered.includes(:customer, :third_party, :legal_entity, :journal_entry, sales_invoice_sources: :source)
                          .limit(LIMITE).to_a
          facture = scope.invoices.sum(:total_cents) - scope.credit_notes.sum(:total_cents)
          impaye = scope.invoices.issued.includes(:credit_notes).sum(&:remaining_cents)
          entete = "Facturé #{euros(facture)} · impayé #{euros(impaye)} · " \
                   "#{Invoicing::Queue.new.requested.size} facture(s) à fournir (a_facturer)"
          return "#{entete}\nAucune facture." if factures.empty?

          "#{entete}\n#{factures.map { |f| ligne_vente(f) }.join("\n")}"
        end

        private

        def ligne_vente(f)
          reste = " · reste dû #{euros(f.remaining_cents)}" if !f.credit_note? && f.issued?
          "##{f.id} #{'NC ' if f.credit_note?}n° #{f.number} · #{f.issued_on} · #{f.customer_name || '—'} · #{euros(f.total_cents)} · " \
            "#{f.status_label.downcase}#{reste} · #{f.legal_entity&.name}#{" · #{sources(f)}" if f.sales_invoice_sources.any?}" \
            "#{" · écriture #{f.journal_entry.reference}" if f.journal_entry}" \
            "#{" · corrige #{f.credited_invoice&.number}" if f.credited_invoice_id}#{' · PDF' if f.document.attached?}"
        end

        def sources(f)
          f.sales_invoice_sources.map { |s| "#{TYPES[source_kind(s.source)] || s.source_type} ##{s.source_id}" }.join(", ")
        end

        def source_kind(source) = Invoicing::Queue::KINDS.key(source.class)

        def a_facturer
          lignes = Invoicing::Queue.new.requested
          return "Aucune facture à fournir." if lignes.empty?

          lignes.map do |l|
            "#{TYPES[l.kind]} ##{l.id} · #{l.label}#{" (#{l.sublabel})" if l.sublabel} · du #{l.from_date || '—'} au #{l.to_date || '—'} · " \
              "#{l.priceless? ? 'SANS MONTANT' : euros(l.price_cents)}"
          end.join("\n")
        end

        def detail(f)
          paiements = f.cash_allocations.includes(:cash_entry).map do |a|
            "  #{euros(a.amount_cents)} · ligne ##{a.cash_entry_id} du #{a.cash_entry&.entry_date} · #{a.cash_entry&.counterparty_name}"
          end
          lignes = f.sales_invoice_lines.includes(:general_account, :team).map do |l|
            "  #{l.general_account&.code} #{l.display_label} · HT #{euros(l.net_amount_cents)} · TVA #{l.vat_rate} % " \
              "#{euros(l.vat_cents)} · TTC #{euros(l.amount_cents)}#{" · #{l.team.name}" if l.team}"
          end
          notes_credit = f.credit_note? ? [] : f.credit_notes.map { |n| "  NC n° #{n.number} · #{n.issued_on} · #{euros(n.total_cents)}" }
          [ligne_vente(f),
           (f.on_payment? ? "Comptabilisée à l'encaissement du séjour (pas d'écriture de vente)." : nil),
           ("Lignes :\n#{lignes.join("\n")}" if lignes.any?),
           ("Notes de crédit :\n#{notes_credit.join("\n")}" if notes_credit.any?),
           ("Notes : #{f.notes}" if f.notes.present?),
           (paiements.any? ? "Payée par :\n#{paiements.join("\n")}" : "Aucun paiement rapproché (rapprocher_ligne facture_vente).")].compact.join("\n")
        end
      end
    end
  end
end
